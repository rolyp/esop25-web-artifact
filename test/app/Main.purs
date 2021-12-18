module Test.App.Main where

import Prelude
import Data.Traversable (sequence)
import Effect (Effect)
import Effect.Aff (Aff)
import Partial.Unsafe (unsafePartial)
import Test.Spec (before, it)
import App.Demo (fig, fig1, figConv1, linkingFig)
import App.Renderer (Fig)
import Test.Util (Test, run)

-- For now app tests just exercise figure creation code.
test_fig :: Aff Fig -> Test Unit
test_fig setup =
   before setup $
      it "hello" \_ ->
         pure unit

tests :: Array (Test Unit)
tests = unsafePartial [test_fig (fig figConv1), test_fig (linkingFig fig1)]

main :: Effect Unit
main = void (sequence (run <$> tests))
