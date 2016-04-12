{-# LANGUAGE FlexibleContexts #-}
module Room where
import Rumpus

roomCube = 4
(roomW, roomH, roomD) = (roomCube,roomCube,roomCube)
wallD = 1
shelfH = 0.15

--roomOffset = (roomH/2 - wallD/2)
roomOffset = 0

start :: Start
start = do
    lhID <- getLeftHandID
    removeEntityComponent myShapeType lhID
    --setPose (identity & translation .~ V3 0 roomOffset (-roomD/2 + 0.4))
    setPose (identity & translation .~ V3 0 10 (-roomD/2 + 0.4))
    removeChildren
    builderID <- ask
    let makeWall pos size hue = spawnEntity $ do
            myParent            ==> builderID
            myPose              ==> mkTransformation 
                (axisAngle (V3 0 0 1) 0) (pos & _y +~ roomOffset)
            myShapeType         ==> CubeShape
            myPhysicsProperties ==> [Kinematic, Static]
            mySize              ==> size
            myColor             ==> hslColor hue 0.8 0.6 1
            myMass              ==> 0
    --makeWall (V3 0 0 (-roomD/2)) (V3 roomW roomH wallD) 0.1 -- back
    makeWall (V3 0 0 (roomD/2))  (V3 roomW roomH wallD) 0.8 -- front
    makeWall (V3 (-roomW/2) 0 0) (V3 wallD roomH roomD) 0.4 -- left
    makeWall (V3 (roomW/2)  0 0) (V3 wallD roomH roomD) 0.5 -- right
    makeWall (V3 0 (-roomH/2) 0) (V3 roomW wallD roomD) 0.6 -- floor
    makeWall (V3 0 (roomH/2)  0) (V3 roomW wallD roomD) 0.9 -- ceiling
    
    let numShelves = 3
    --forM_ [1..numShelves] $ \n -> do
    forM_ [1,3] $ \n -> do
        let shelfY = (roomH/realToFrac (succ numShelves)) 
                        * fromIntegral n - (roomH/2)
        makeWall (V3 0 shelfY (roomD/2)) 
                 (V3 roomW shelfH (wallD*2)) 0.7 -- shelf


    spawnEntity $ do
        myParent            ==> builderID
        myPose              ==> mkTransformation 
            (axisAngle (V3 0 0 1) 0) (V3 0 roomOffset 2)
        myShapeType         ==> SphereShape
        myPhysicsProperties ==> [Kinematic, Static]
        mySize              ==> 0.8
        myColor             ==> hslColor 0.2 0.7 0.6
        myMass              ==> 0

    return Nothing
