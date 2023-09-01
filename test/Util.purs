module Test.Util where

import Prelude hiding (absurd)

import App.Fig (LinkFigSpec, linkResult, loadLinkFig)
import App.Util (Selector)
import Benchmark.Util (BenchmarkAcc(..), getCurr, logTime)
import Control.Monad.Error.Class (class MonadThrow)
import Control.Monad.Except (except, runExceptT)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Writer (WriterT(..), runWriterT)
import Data.Either (Either(..))
import Data.List (elem)
import Data.Set (Set) as S
import Data.String (null)
import Data.Traversable (traverse_)
import Data.Tuple (fst)
import DataType (dataTypeFor, typeName)
import Debug (trace)
import Desugarable (desug, desugBwd)
import Effect (Effect)
import Effect.Aff (Aff)
import Effect.Class.Console (log)
import Effect.Exception (Error)
import Eval (eval)
import EvalBwd (evalBwd)
import EvalGraph (GraphConfig, evalWithConfig)
import Graph (sinks, sources, vertices)
import Graph.GraphImpl (GraphImpl)
import Graph.Slice (bwdSlice, fwdSlice) as G
import Graph.Slice (selectVertices, select𝔹s)
import Lattice (bot, botOf, erase)
import Module (File(..), Folder(..), loadFile, open, openDatasetAs, openDefaultImports, parse)
import Parse (program)
import Pretty (class Pretty, prettyP)
import SExpr (Expr) as SE
import Set (subset)
import Test.Spec (SpecT(..), before, beforeAll, beforeWith, it)
import Test.Spec.Assertions (fail)
import Test.Spec.Mocha (runMocha)
import Util (Endo, MayFailT, type (×), (×), successful)
import Val (Val(..), class Ann, (<+>))

-- Don't enforce fwd_expect values for graphics tests (values too complex).
isGraphical :: forall a. Val a -> Boolean
isGraphical (Constr _ c _) = typeName (successful (dataTypeFor c)) `elem` [ "GraphicsElement", "Plot" ]
isGraphical _ = false

type Test a = SpecT Aff Unit BenchmarkAcc a
type TestWith g a = SpecT Aff g BenchmarkAcc a

unBenchAcc :: forall a. Boolean -> BenchmarkAcc a -> Effect a
unBenchAcc _is_bench (BAcc ba) = map fst $ runWriterT ba

unWriterTest :: forall a. Boolean -> Test a -> SpecT Aff Unit Effect a
unWriterTest is_bench (SpecT (WriterT monadic)) = (SpecT (WriterT (unBenchAcc is_bench monadic)))

run :: forall a. Test a → Effect Unit
run test = runMocha $ unWriterTest false test -- no reason at all to see the word "Mocha"

checkPretty :: forall a m. MonadThrow Error m => Pretty a => String -> String -> a -> m Unit
checkPretty msg expect x =
   unless (expect `eq` prettyP x)
      $ fail (msg <> "\nExpected:\n" <> expect <> "\nGotten:\n" <> prettyP x)

-- Like version in Test.Spec.Assertions but with error message.
shouldSatisfy :: forall m t. MonadThrow Error m => Show t => String -> t -> (t -> Boolean) -> m Unit
shouldSatisfy msg v pred =
   unless (pred v)
      $ fail
      $ show v <> " doesn't satisfy predicate: " <> msg

type TestConfig =
   { δv :: Selector Val
   , fwd_expect :: String
   , bwd_expect :: String
   }

-- fwd_expect: prettyprinted value after bwd then fwd round-trip
testWithSetup :: Boolean -> SE.Expr Unit -> GraphConfig (GraphImpl S.Set) -> TestConfig -> Aff Unit
testWithSetup is_bench s gconfig tconfig =
   runExceptT
      ( do
           unless is_bench (testParse s)
           testTrace is_bench s gconfig tconfig
           testGraph is_bench s gconfig tconfig
      ) >>=
      case _ of
         Left msg -> fail msg
         Right unit -> pure unit

testParse :: forall a. Ann a => SE.Expr a -> MayFailT Aff Unit
testParse s = do
   let src = prettyP s
   s' <- parse src program
   trace ("Non-Annotated:\n" <> src)
      ( \_ ->
           unless (eq (erase s) (erase s')) do
              log ("SRC\n" <> show (erase s))
              log ("NEW\n" <> show (erase s'))
              lift $ fail "not equal"
      )

testTrace :: Boolean -> SE.Expr Unit -> GraphConfig (GraphImpl S.Set) -> TestConfig -> MayFailT Aff Unit
testTrace is_bench s { γ } { δv, bwd_expect, fwd_expect } = do
   let s𝔹 × γ𝔹 = (botOf s) × (botOf <$> γ)
   -- | Eval
   pre_desug <- getCurr
   e𝔹 <- desug s𝔹
   pre_eval <- getCurr
   t × v𝔹 <- eval γ𝔹 e𝔹 bot
   post_eval <- getCurr

   -- | Backward
   pre_slice <- getCurr
   let
      v𝔹' = δv v𝔹
      { γ: γ𝔹', e: e𝔹' } = evalBwd (erase <$> γ𝔹) (erase e𝔹) v𝔹' t
   post_slice <- getCurr

   let
      s𝔹' = desugBwd e𝔹' s
   -- | Forward (round-tripping)
   e𝔹'' <- desug s𝔹'
   pre_fwd_slice <- getCurr
   _ × v𝔹'' <- eval γ𝔹' e𝔹'' top
   post_fwd_slice <- getCurr

   if not is_bench then
      lift $ do
         -- | Check backward selections
         unless (null bwd_expect) do
            checkPretty "Trace-based source selection" bwd_expect s𝔹'
         -- | Check round-trip selections
         unless (isGraphical v𝔹') do
            checkPretty "Trace-based value" fwd_expect v𝔹''
   else
      lift $ do
         logTime "Desug time: " pre_desug pre_eval
         logTime "Trace-based eval: " pre_eval post_eval
         logTime "Trace-based bwd slice time: " pre_slice post_slice
         logTime "Trace-based fwd slice time:" pre_fwd_slice post_fwd_slice

testGraph :: Boolean -> SE.Expr Unit -> GraphConfig (GraphImpl S.Set) -> TestConfig -> MayFailT Aff Unit
testGraph is_bench s gconf { δv, bwd_expect, fwd_expect } = do
   -- | Eval
   e <- desug s
   pre_eval <- getCurr
   (g × _) × (eα × vα) <- evalWithConfig gconf e >>= except
   post_eval <- getCurr
   -- | Backward
   pre_slice <- getCurr
   let
      αs_out = selectVertices (δv (botOf vα)) vα
      gbwd = G.bwdSlice αs_out g
      αs_in = sinks gbwd
   post_slice <- getCurr
   let
      e𝔹 = select𝔹s eα αs_in
      s𝔹 = desugBwd e𝔹 (erase s)
   -- | Forward (round-tripping)
   pre_fwd_slice <- getCurr
   let
      gfwd = G.fwdSlice αs_in g
      v𝔹 = select𝔹s vα (vertices gfwd)
   post_fwd_slice <- getCurr
   {- | Forward (round-tripping) using De Morgan dual
      gfwd' = G.fwdSliceDeMorgan αs_in g
      v𝔹' = select𝔹s vα (vertices gfwd') <#> not
   -}
   if not is_bench then
      lift $ do
         -- | Check backward selections
         unless (null bwd_expect) do
            checkPretty "Graph-based source selection" bwd_expect s𝔹
         -- | Check round-trip selections
         unless (isGraphical v𝔹) do
            checkPretty "Graph-based value" fwd_expect v𝔹
         -- checkPretty "Graph-based value (De Morgan)" fwd_expect v𝔹'
         sources gbwd `shouldSatisfy "fwd ⚬ bwd round-tripping property"`
            (flip subset (sources gfwd))
   else
      lift $ do
         logTime "Graph-based eval time: " pre_eval post_eval
         logTime "Graph-based bwd slice time: " pre_slice post_slice
         logTime "Graph-based fwd slice time: " pre_fwd_slice post_fwd_slice

withDefaultImports ∷ TestWith (GraphConfig (GraphImpl S.Set)) Unit -> Test Unit
withDefaultImports x = beforeAll openDefaultImports x

withDataset :: File -> TestWith (GraphConfig (GraphImpl S.Set)) Unit -> TestWith (GraphConfig (GraphImpl S.Set)) Unit
withDataset dataset =
   beforeWith (openDatasetAs dataset "data" >=> (\({ g, n, γ } × xv) -> pure { g, n, γ: γ <+> xv }))

testMany :: Boolean -> Array (File × String) → Test Unit
testMany is_bench fxs = withDefaultImports $ traverse_ test fxs
   where
   test :: File × String -> SpecT Aff (GraphConfig (GraphImpl S.Set)) BenchmarkAcc Unit
   test (file × fwd_expect) = beforeWith ((_ <$> open file) <<< (×)) $
      it (show file) (\(gconfig × s) -> testWithSetup is_bench s gconfig { δv: identity, fwd_expect, bwd_expect: mempty })

testBwdMany :: Boolean -> Array (File × File × Selector Val × String) → Test Unit
testBwdMany is_bench fxs = withDefaultImports $ traverse_ testBwd fxs
   where
   testBwd :: File × File × (Endo (Val Boolean)) × String -> SpecT Aff (GraphConfig (GraphImpl S.Set)) BenchmarkAcc Unit
   testBwd (file × file_expect × δv × fwd_expect) =
      beforeWith ((_ <$> open (folder <> file)) <<< (×)) $
         it (show $ folder <> file)
            ( \(gconfig × s) -> do
                 bwd_expect <- loadFile (Folder "fluid/example") (folder <> file_expect)
                 testWithSetup is_bench s gconfig { δv, fwd_expect, bwd_expect }
            )
   folder = File "slicing/"

testWithDatasetMany :: Boolean -> Array (File × File) -> Test Unit
testWithDatasetMany is_bench fxs = withDefaultImports $ traverse_ testWithDataset fxs
   where
   testWithDataset :: File × File -> SpecT Aff (GraphConfig (GraphImpl S.Set)) BenchmarkAcc Unit
   testWithDataset (dataset × file) = withDataset dataset $ beforeWith ((_ <$> open file) <<< (×)) do
      it (show file) (\(gconfig × s) -> testWithSetup is_bench s gconfig { δv: identity, fwd_expect: mempty, bwd_expect: mempty })

testLinkMany :: Array (LinkFigSpec × Selector Val × String) -> Test Unit
testLinkMany fxs = traverse_ testLink fxs
   where
   testLink (spec@{ x } × δv1 × v2_expect) = before (loadLinkFig spec) $
      it ("linking/" <> show spec.file1 <> " <-> " <> show spec.file2)
         \{ γ0, γ, e1, e2, t1, t2, v1 } ->
            let
               { v': v2' } = successful $ linkResult x γ0 γ e1 e2 t1 t2 (δv1 v1)
            in
               checkPretty "Linked output" v2_expect v2'
