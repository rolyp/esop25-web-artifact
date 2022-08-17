 module Test.Util2 where

import Prelude hiding (absurd)
import Data.List (elem)
import Data.Maybe (Maybe(..){-, fromMaybe-})
import Data.Tuple ({-fst, -}snd)
import Debug (trace)
import Effect (Effect)
import Effect.Aff (Aff)
import Test.Spec (SpecT, before, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Mocha (runMocha)
--import App.Fig2 (LinkFigSpec, linkResult, loadLinkFig)
import App.Util2 (Selector)
import DataType2 (dataTypeFor, typeName)
--import DesugarBwd2 (desugarBwd)
import DesugarFwd2 (desugarFwd)
import Eval2 (eval)
--import EvalBwd2 (evalBwd)
--import EvalFwd2 (evalFwd)
import Expl2 (Expl)
import SExpr2 (Expr) as S
import Lattice2 (𝔹)
import Module2 (File(..), {-Folder(..), loadFile, -}open, openDatasetAs, openWithDefaultImports)
import Pretty2 (class Pretty, prettyP)
import Util2 (MayFail, type (×), (×), successful)
import Val2 (Env2, Val(..), concat)

-- Don't enforce expected values for graphics tests (values too complex).
isGraphical :: forall a . Val a -> Boolean
isGraphical (Constr _ c _) = typeName (successful (dataTypeFor c)) `elem` ["GraphicsElement", "Plot"]
isGraphical _              = false

type Test a = SpecT Aff Unit Effect a

run :: forall a . Test a → Effect Unit
run = runMocha -- no reason at all to see the word "Mocha"

desugarEval :: Env2 𝔹 -> S.Expr 𝔹 -> MayFail (Expl 𝔹 × Val 𝔹)
desugarEval ρ s = desugarFwd s >>= eval ρ

{-
desugarEval_bwd :: Expl 𝔹 × S.Expr 𝔹 -> Val 𝔹 -> Env 𝔹 × S.Expr 𝔹
desugarEval_bwd (t × s) v =
   let ρ × e × _ = evalBwd v t in
   ρ × desugarBwd e s

desugarEval_fwd :: Env 𝔹 -> S.Expr 𝔹 -> Expl 𝔹 -> Val 𝔹
desugarEval_fwd ρ s = evalFwd ρ (successful (desugarFwd s)) true
-}

checkPretty :: forall a . Pretty a => String -> String -> a -> Aff Unit
checkPretty msg expected x =
   trace (msg <> ":\n" <> prettyP x) \_ ->
      prettyP x `shouldEqual` expected

-- v_expect_opt is optional output slice + expected source slice; expected is expected result after round-trip.
testWithSetup :: File -> String -> Maybe (Val 𝔹 × File) -> Aff (Env2 𝔹 × S.Expr 𝔹) -> Test Unit
testWithSetup (File file) expected v_expect_opt setup =
   before setup $
      it file \(ρ × s) -> do
         let _ × v = successful (desugarEval ρ s)
             --ρ' × s' = desugarEval_bwd (t × s) (fromMaybe v (fst <$> v_expect_opt))
             --v' = desugarEval_fwd ρ' s' t
         --unless (isGraphical v') (checkPretty "Value" expected v')
         unless (isGraphical v) (checkPretty "Value" expected v)
         case snd <$> v_expect_opt of
            Nothing -> pure unit
            Just _{-file_expect-} ->
               pure unit
               --loadFile (Folder "fluid/example") file_expect >>= flip (checkPretty "Source selection") s'

-- v_expect_opt is optional output slice + expected source slice; expected is expected result after round-trip.
testWithSetup2 :: File -> String -> Maybe (Selector × File) -> Aff (Env2 𝔹 × S.Expr 𝔹) -> Test Unit
testWithSetup2 (File file) expected v_expect_opt setup =
   before setup $
      it file \(ρ × s) -> do
         let _ × v = successful (desugarEval ρ s)
             --ρ' × s' = desugarEval_bwd (t × s) (fromMaybe v (fst <$> v_expect_opt))
             --v' = desugarEval_fwd ρ' s' t
         --unless (isGraphical v') (checkPretty "Value" expected v')
         unless (isGraphical v) (checkPretty "Value" expected v)
         case snd <$> v_expect_opt of
            Nothing -> pure unit
            Just _{-file_expect-} ->
               pure unit
               --loadFile (Folder "fluid/example") file_expect >>= flip (checkPretty "Source selection") s'

test :: File -> String -> Test Unit
test file expected = testWithSetup file expected Nothing (openWithDefaultImports file)

testBwd :: File -> File -> Selector -> String -> Test Unit
testBwd file file_expect δv expected =
   let folder = File "slicing/"
       file' = folder <> file in
   testWithSetup2 file' expected (Just (δv × (folder <> file_expect))) (openWithDefaultImports file')

{-
testLink :: LinkFigSpec -> Val 𝔹 -> String -> Test Unit
testLink spec@{ x } v1' v2_expect =
   before (loadLinkFig spec) $
      it ("linking/" <> show spec.file1 <> " <-> " <> show spec.file2)
         \{ ρ0, e2, t1, t2 } ->
            let { v': v2' } = successful $ linkResult x ρ0 e2 t1 t2 v1' in
            checkPretty "Linked output" v2_expect v2'
-}
testWithDataset :: File -> File -> Test Unit
testWithDataset dataset file = do
   testWithSetup file "" Nothing $ do
      ρ0 × ρ <- openDatasetAs dataset "data"
      let ρ' = ρ0 `concat` ρ
      (ρ' × _) <$> open file
