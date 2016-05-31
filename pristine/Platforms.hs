module Platforms where
import Rumpus

-- Platform extent in x & z
w = 4
-- Platform depth in y
d = 0.5

start :: Start
start = do
    let platform pos size hue = spawnChild $ do
            myPose       ==> translateMatrix (pos & _y -~ (size^._y/2))
            myShape      ==> Cube
            myProperties ==> [Teleportable, Floating, Ungrabbable]
            mySize       ==> size
            myColor      ==> colorHSL hue 0.8 0.6
            myMass       ==> 0

    -- Platforms
    platform (V3 0     0  0)     (V3 w d w) 0.1
    platform (V3 (-10) 0  0)     (V3 w d w) 0.1
    platform (V3 (10)  0  0)     (V3 w d w) 0.1
    platform (V3 0     0  (-10)) (V3 w d w) 0.1
    platform (V3 0     0  (10))  (V3 w d w) 0.1
    platform (V3 0     10 (-20)) (V3 w d w) 0.5

    return ()