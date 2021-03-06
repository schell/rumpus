module Cloud where
import Rumpus

start::Start
start = do
    cloudID <- ask
    let numPuffs = 5
    forM_ [0..numPuffs] $ \i -> do
        hue <- randomRange (0.5, 0.6)

        x <- (0.5 + i / numPuffs +) <$> randomRange (0,0.2)
        y <- randomRange (-0.1,0.1)
        z <- randomRange (-0.1,0.1)
        puffID <- spawnChild $ do
            myShape  ==> Sphere
            myColor  ==> colorHSL hue 0.5 0.5
            myPose   ==> position (V3 x y z)
            myUpdate ==> do
                now <- (i +) <$> getNow
                setSize (realToFrac (sin now / 2 + 1) * 0.2 + 0.2) -- 0.2<->0.4
        inEntity puffID $ setRepeatingAction (1/4) $ do
            chance <- randomRange (0,1::Int)
            when (chance == 0) $ do
                cloudPose <- getEntityPose cloudID
                startPos <- V3 <$> pure x
                               <*> randomRange (-0.1, 0.1)
                               <*> randomRange (-0.1, 0.1)
                hue <- randomRange (0.5,0.7)
                spawnChild_ $ do
                    myShape ==> Sphere
                    myPose  ==> cloudPose !*! position startPos
                    mySize  ==> 0.03
                    myBody  ==> Physical
                    myColor ==> colorHSL hue 0.5 0.8
                    myLifetime ==> 2
