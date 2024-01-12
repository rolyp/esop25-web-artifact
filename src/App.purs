module App where

import Prelude hiding (absurd)

import App.Fig (FigSpec, drawFigWithCode, drawFile, drawLinkedOutputsFigWithCode, loadFig, loadLinkedOutputsFig, runAffs_)
import Effect (Effect)
import Module (File(..), Folder(..), loadFile')
import Test.Specs (linkedOutputs_spec1)

fig1 :: FigSpec
fig1 =
   { divId: "fig-conv-1"
   , file: File "slicing/convolution/emboss"
   , imports:
        [ "lib/convolution"
        , "example/slicing/convolution/test-image"
        , "example/slicing/convolution/filter/emboss"
        ]
   , datasets: []
   , ins: [ "image", "filter" ]
   }

fig2 :: FigSpec
fig2 =
   { divId: "fig-conv-2"
   , file: File "slicing/convolution/emboss-wrap"
   , imports:
        [ "lib/convolution"
        , "example/slicing/convolution/test-image"
        , "example/slicing/convolution/filter/emboss"
        ]
   , datasets: []
   , ins: [ "image", "filter" ]
   }

main :: Effect Unit
main = do
   runAffs_ drawFile [ loadFile' (Folder "fluid/lib") (File "convolution") ]
   runAffs_ drawFigWithCode [ loadFig fig1, loadFig fig2 ]
   runAffs_ drawLinkedOutputsFigWithCode [ loadLinkedOutputsFig linkedOutputs_spec1.spec ]
