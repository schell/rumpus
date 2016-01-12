{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE DeriveDataTypeable #-}
module Rumpus.Main where
import Graphics.VR.Pal
import Graphics.GL.Pal
import Graphics.GL.Freetype

import Control.Monad
import Control.Monad.State
import Control.Lens.Extra
import Data.Maybe
import Control.Monad.Reader
import Data.Foldable
import Control.Concurrent.STM
import Data.Yaml hiding ((.=))

import qualified Data.Map as Map

import Physics.Bullet
import Sound.Pd
import TinyRick

import qualified Spatula

import Rumpus.Render
import Rumpus.Entity
import Rumpus.Types
import Rumpus.Control

createCodeEditorSystem = do
    ghcChan   <- startGHC ["app"]
    glyphProg <- createShaderProgram "resources/shaders/glyph.vert" "resources/shaders/glyph.frag"
    font      <- createFont "resources/fonts/SourceCodePro-Regular.ttf" 50 glyphProg

    return (font, ghcChan)

createRenderSystem :: IO [(ShapeType, Shape Uniforms)]
createRenderSystem = do
    glEnable GL_DEPTH_TEST
    glClearColor 0 0 0.1 1

    basicProg   <- createShaderProgram "resources/shaders/default.vert" "resources/shaders/default.frag"

    cubeGeo     <- cubeGeometry (V3 1 1 1) 1
    sphereGeo   <- icosahedronGeometry 1 5 -- radius subdivisions
    planeGeo    <- planeGeometry 1 (V3 0 0 1) (V3 0 1 0) 1
    
    planeShape  <- makeShape planeGeo  basicProg
    cubeShape   <- makeShape cubeGeo   basicProg
    sphereShape <- makeShape sphereGeo basicProg

    let shapes = [(CubeShape, cubeShape), (SphereShape, sphereShape), (StaticPlaneShape, planeShape)]
    return shapes

createPhysicsSystem :: IO DynamicsWorld
createPhysicsSystem = createDynamicsWorld mempty

main :: IO ()
main = withPd $ \pd -> do
    mapM_ (addToLibPdSearchPath pd)
        ["resources/pd-kit", "resources/pd-kit/list-abs"]

    vrPal  <- initVRPal "Rumpus" [UseOpenVR]

    shapes <- createRenderSystem
    (font, ghcChan) <- createCodeEditorSystem

    dynamicsWorld <- createPhysicsSystem

    let worldStatic = WorldStatic
            { _wlsDynamicsWorld = dynamicsWorld
            , _wlsShapes        = shapes
            , _wlsVRPal         = vrPal
            , _wlsPd            = pd
            , _wlsFont          = font
            , _wlsGHCChan       = ghcChan
            }
        world = newWorld & wldOpenALSourcePool .~ zip [1..] (pdSources pd)
                         & wldPlayer .~ if gpRoomScale vrPal == RoomScale 
                                        then newPose
                                        else newPose & posPosition .~ V3 0 1 5

    void . flip runReaderT worldStatic . flip runStateT world $ do 

        loadScene "spatula/spatula.yaml"

        whileVR vrPal $ \headM44 hands -> do
            
            -- Collect control events into the events channel to be read by entities during update
            controlEventsSystem headM44 hands

            attachmentsSystem

            isPlaying <- use wldPlaying
            if isPlaying  
                then do
                    scriptingSystem
                                        
                    physicsSystem
                    
                    syncPhysicsPosesSystem

                    -- collisionsSystem

                    editingSystem
                else do
                    performDiscreteCollisionDetection dynamicsWorld

                    editingSystem

            openALSystem headM44

            renderSystem headM44

editingSystem :: WorldMonad ()
editingSystem = do
    let editSceneWithHand handName event = do
            mHandEntityID <- listToMaybe <$> getEntityIDsWithName handName
            forM_ mHandEntityID $ \handEntityID -> case event of
                HandStateEvent hand -> 
                    setEntityPose (poseFromMatrix (hand ^. hndMatrix)) handEntityID
                HandButtonEvent HandButtonTrigger ButtonDown -> do
                    -- Find the entities overlapping the hand, and attach them to it
                    overlappingEntityIDs <- filterM (fmap (/= "Floor") . getEntityName) 
                                            =<< getEntityGhostOverlappingEntityIDs handEntityID
                    forM_ (listToMaybe overlappingEntityIDs) $ \touchedID -> do
                        name <- getEntityName touchedID
                        when (name /= "Floor") $ 
                            attachEntity handEntityID touchedID
                HandButtonEvent HandButtonTrigger ButtonUp -> do
                    -- Copy the current pose to the scene file and save it
                    withAttachment handEntityID $ \(Attachment attachedEntityID _offset) -> do
                        currentPose <- getEntityPose attachedEntityID
                        wldScene . at attachedEntityID . traverse . entPose .= currentPose
                        saveScene
                    detachEntity handEntityID
                _ -> return ()

    withLeftHandEvents (editSceneWithHand "Left Hand")
    withRightHandEvents (editSceneWithHand "Right Hand")

loadScene sceneFile =     
    liftIO (decodeFileEither sceneFile) >>= \case
        Left parseException -> putStrLnIO ("Error loading " ++ sceneFile ++ ": " ++ show parseException)
        Right entities -> do
            forM_ (entities :: [(EntityID, Entity)]) $ \(entityID, entity) -> 
                createEntityWithID Persistent entityID entity

saveScene = do
    let sceneFile = "spatula/spatula.yaml"
    scene <- use wldScene
    liftIO $ encodeFile sceneFile (Map.toList scene)


attachmentsSystem :: (MonadIO m, MonadState World m, MonadReader WorldStatic m) => m ()
attachmentsSystem = do
    attachments <- Map.toList <$> use (wldComponents . cmpAttachment)
    forM_ attachments $ \(entityID, Attachment toEntityID offset) -> do
        pose <- getEntityPose entityID
        setEntityPose (addPoses pose offset) toEntityID

scriptingSystem :: WorldMonad ()
scriptingSystem = do
    traverseM_ (Map.toList <$> use (wldComponents . cmpScript)) $ 
        \(entityID, editor) -> do
            updateFunc <- liftIO $ getEditorValue editor (\eid -> return ()) id
            errors <- liftIO . atomically $ readTVar (edErrors editor)
            -- printIO errors
            updateFunc entityID


renderSystem :: (MonadIO m, MonadState World m, MonadReader WorldStatic m) => M44 GLfloat -> m ()
renderSystem headM44 = do
    vrPal <- view wlsVRPal
    -- Render the scene
    player <- use wldPlayer
    renderWith vrPal player headM44
        (glClear (GL_COLOR_BUFFER_BIT .|. GL_DEPTH_BUFFER_BIT))
        renderSimulation

physicsSystem :: (MonadIO m, MonadReader WorldStatic m) => m ()
physicsSystem = do
    dynamicsWorld <- view wlsDynamicsWorld
    stepSimulation dynamicsWorld 90

syncPhysicsPosesSystem :: (MonadIO m, MonadState World m, MonadReader WorldStatic m) => m ()
syncPhysicsPosesSystem = do
    -- Sync rigid bodies with entity poses
    traverseM_ (Map.toList <$> use (wldComponents . cmpRigidBody)) $ 
        \(entityID, rigidBody) -> do
            pose <- uncurry Pose <$> getBodyState rigidBody
            wldComponents . cmpPose . at entityID ?= pose



-- collisionsSystem :: WorldMonad ()
-- collisionsSystem = do
--     dynamicsWorld <- view wlsDynamicsWorld
--     -- Tell objects about any collisions
--     collisions <- getCollisions dynamicsWorld
    
--     forM_ collisions $ \collision -> do
--         let bodyAID = (fromIntegral . unCollisionObjectID . cbBodyAID) collision
--             bodyBID = (fromIntegral . unCollisionObjectID . cbBodyBID) collision
--             appliedImpulse = cbAppliedImpulse collision
--         mapM_ (\onCollision -> onCollision bodyAID bodyBID appliedImpulse)
--             =<< use (wldComponents . cmpCollision . at bodyAID)
--         mapM_ (\onCollision -> onCollision bodyBID bodyAID appliedImpulse)
--             =<< use (wldComponents . cmpCollision . at bodyBID)

openALSystem :: (MonadIO m, MonadState World m, MonadReader WorldStatic m) => M44 GLfloat -> m ()
openALSystem headM44 = do
    -- Update souce and listener poitions
    alListenerPose (poseFromMatrix headM44)
    mapM_ (\(entityID, sourceID) -> do
        position <- view posPosition <$> getEntityPose entityID
        alSourcePosition sourceID position)
        =<< Map.toList <$> use (wldComponents . cmpSoundSource)