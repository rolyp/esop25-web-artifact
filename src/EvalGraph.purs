module EvalGraph
   ( apply
   , eval
   , evalGraph
   , eval_module
   , match
   , matchMany
   , patternMismatch
   ) where

import Prelude hiding (apply, add)

import Bindings (varAnon)
import Control.Monad.Except (except)
import Control.Monad.State (get)
import Control.Monad.Trans.Class (lift)
import Data.Array (range, singleton) as A
import Data.Either (Either(..), note)
import Data.Exists (runExists)
import Data.List (List(..), (:), length, snoc, unzip, zip)
import Data.Set as S
import Data.Traversable (sequence, traverse)
import Data.Tuple (fst)
import DataType (checkArity, arity, consistentWith, dataTypeFor, showCtr)
import Debug (trace)
import Dict (disjointUnion, fromFoldable, empty, get, keys, lookup, singleton) as D
import Expr (Cont(..), Elim(..), Expr(..), VarDef(..), RecDefs, Module(..), fv, asExpr)
import Graph (Vertex, class Graph)
import Graph (empty) as G
import Graph.GraphWriter (WithGraphT, alloc, new, runWithGraphT)
import Pretty (prettyP)
import Primitive (string, intPair)
import Set (class Set, insert, empty, singleton, union)
import Util (type (×), (×), MayFail, check, error, report, successful, with)
import Util.Pair (unzip) as P
import Val (Val(..), Fun(..)) as V
import Val (DictRep(..), Env, ForeignOp'(..), MatrixRep(..), Val, for, lookup', restrict, (<+>))

{-# Matching #-}
patternMismatch :: String -> String -> String
patternMismatch s s' = "Pattern mismatch: found " <> s <> ", expected " <> s'

match :: forall s. Set s Vertex => Val Vertex -> Elim Vertex -> MayFail (Env Vertex × Cont Vertex × s Vertex)
match v (ElimVar x κ)
   | x == varAnon = pure (D.empty × κ × empty)
   | otherwise = pure (D.singleton x v × κ × empty)
match (V.Constr α c vs) (ElimConstr m) = do
   with "Pattern mismatch" $ S.singleton c `consistentWith` D.keys m
   κ <- note ("Incomplete patterns: no branch for " <> showCtr c) (D.lookup c m)
   γ × κ' × αs <- matchMany vs κ
   pure (γ × κ' × (insert α αs))
match v (ElimConstr m) = do
   d <- dataTypeFor $ D.keys m
   report $ patternMismatch (prettyP v) (show d)
match (V.Record α xvs) (ElimRecord xs κ) = do
   check (S.subset xs (S.fromFoldable $ D.keys xvs))
      $ patternMismatch (show (D.keys xvs)) (show xs)
   let xs' = xs # S.toUnfoldable
   γ × κ' × αs <- matchMany (flip D.get xvs <$> xs') κ
   pure $ γ × κ' × (insert α αs)
match v (ElimRecord xs _) = report (patternMismatch (prettyP v) (show xs))

matchMany :: forall s. Set s Vertex => List (Val Vertex) -> Cont Vertex -> MayFail (Env Vertex × Cont Vertex × s Vertex)
matchMany Nil κ = pure (D.empty × κ × empty)
matchMany (v : vs) (ContElim σ) = do
   γ × κ × αs <- match v σ
   γ' × κ' × βs <- matchMany vs κ
   pure $ γ `D.disjointUnion` γ' × κ' × (αs `union` βs)
matchMany (_ : vs) (ContExpr _) = report $
   show (length vs + 1) <> " extra argument(s) to constructor/record; did you forget parentheses in lambda pattern?"
matchMany _ _ = error "absurd"

closeDefs :: forall s m. Monad m => Set s Vertex => Env Vertex -> RecDefs Vertex -> s Vertex -> WithGraphT s m (Env Vertex)
closeDefs γ ρ αs =
   flip traverse ρ \σ ->
      let
         ρ' = ρ `for` σ
      in
         V.Fun <$> (V.Closure <$> new αs <@> (γ `restrict` (fv ρ' `S.union` fv σ)) <@> ρ' <@> σ)

{-# Evaluation #-}
apply :: forall s m. Monad m => Set s Vertex => Val Vertex -> Val Vertex -> WithGraphT s m (Val Vertex)
apply (V.Fun (V.Closure α γ1 ρ σ)) v = do
   γ2 <- closeDefs γ1 ρ (singleton α)
   γ3 × κ × αs <- except $ match v σ
   eval (γ1 <+> γ2 <+> γ3) (asExpr κ) (insert α αs)
apply (V.Fun (V.PartialConstr α c vs)) v = do
   let n = successful (arity c)
   except $ check (length vs < n) ("Too many arguments to " <> showCtr c)
   let
      v' =
         if length vs < n - 1 then V.Fun $ V.PartialConstr α c (snoc vs v)
         else V.Constr α c (snoc vs v)
   pure v'
apply (V.Fun (V.Foreign φ vs)) v = do
   let vs' = snoc vs v
   let
      apply' :: forall t. ForeignOp' t -> WithGraphT s m (Val Vertex)
      apply' (ForeignOp' φ') =
         if φ'.arity > length vs' then pure $ V.Fun (V.Foreign φ vs')
         else φ'.op' vs'
   runExists apply' φ
apply _ v = except $ report $ "Found " <> prettyP v <> ", expected function"

eval :: forall s m. Monad m => Set s Vertex => Env Vertex -> Expr Vertex -> s Vertex -> WithGraphT s m (Val Vertex)
eval γ (Var x) _ = except $ lookup' x γ
eval γ (Op op) _ = except $ lookup' op γ
eval _ (Int α n) αs = V.Int <$> new (insert α αs) <@> n
eval _ (Float α n) αs = V.Float <$> new (insert α αs) <@> n
eval _ (Str α s) αs = V.Str <$> new (insert α αs) <@> s
eval γ (Record α xes) αs = do
   xvs <- traverse (flip (eval γ) αs) xes
   V.Record <$> new (insert α αs) <@> xvs
eval γ (Dictionary α ees) αs = do
   vs × us <- traverse (traverse (flip (eval γ) αs)) ees <#> P.unzip
   let
      ss × βs = (vs <#> string.match) # unzip
      d = D.fromFoldable $ zip ss (zip βs us)
   V.Dictionary <$> new (insert α αs) <@> DictRep d
eval γ (Constr α c es) αs = do
   except $ checkArity c (length es)
   vs <- traverse (flip (eval γ) αs) es
   V.Constr <$> new (insert α αs) <@> c <@> vs
eval γ (Matrix α e (x × y) e') αs = do
   v <- eval γ e' αs
   let (i' × β) × (j' × β') = fst (intPair.match v)
   except $ check
      (i' × j' >= 1 × 1)
      ("array must be at least (" <> show (1 × 1) <> "); got (" <> show (i' × j') <> ")")
   vss <- sequence $ do
      i <- A.range 1 i'
      A.singleton $ sequence $ do
         j <- A.range 1 j'
         let γ' = D.singleton x (V.Int β i) `D.disjointUnion` (D.singleton y (V.Int β' j))
         A.singleton (eval (γ <+> γ') e αs)
   V.Matrix <$> new (insert α αs) <@> MatrixRep (vss × (i' × β) × (j' × β'))
eval γ (Lambda σ) αs =
   V.Fun <$> (V.Closure <$> new αs <@> γ `restrict` fv σ <@> D.empty <@> σ)
eval γ (Project e x) αs = do
   v <- eval γ e αs
   except $ case v of
      V.Record _ xvs -> lookup' x xvs
      _ -> report $ "Found " <> prettyP v <> ", expected record"
eval γ (App e e') αs = do
   v <- eval γ e αs
   v' <- eval γ e' αs
   apply v v'
eval γ (Let (VarDef σ e) e') αs = do
   v <- eval γ e αs
   γ' × _ × (αs' :: s Vertex) <- except $ match v σ -- terminal meta-type of eliminator is meta-unit
   eval (γ <+> γ') e' αs' -- (αs ∧ αs') for consistency with functions? (similarly for module defs)
eval γ (LetRec ρ e) αs = do
   γ' <- closeDefs γ ρ αs
   eval (γ <+> γ') e αs

evalEnv :: forall g s m a. Monad m => Graph g s => Env a -> m ((g × Int) × Env Vertex)
evalEnv γ = successful <$> runWithGraphT (G.empty × 0) (traverse alloc γ)

evalWithEnv :: forall g s m a. Monad m => Graph g s => (g × Int) -> Env Vertex -> Expr a -> m ((g × Int) × (Expr Vertex × Val Vertex))
evalWithEnv (g0 × n0) γα e = successful <$> runWithGraphT (g0 × n0) doEval
   where
   doEval :: WithGraphT s m _
   doEval = do
      eα <- alloc e
      n × _ <- lift $ get
      vα <- eval γα eα empty :: WithGraphT s m _
      n' × _ <- lift $ get
      trace (show (n' - n) <> " vertices allocated during eval.") \_ ->
         pure (eα × vα)

evalGraph :: forall g s m a. Monad m => Graph g s => Env a -> Expr a -> m (g × (Env Vertex × Expr Vertex × Val Vertex))
evalGraph γ e = do
   (g × n) × γα <- evalEnv γ
   (g' × _) × (eα × vα) <- evalWithEnv (g × n) γα e
   pure (g' × γα × eα × vα)

eval_module :: forall m s a. Monad m => Set s Vertex => Env Vertex -> Module a -> s Vertex -> WithGraphT s m (Env Vertex)
eval_module γ mod αs0 = alloc_module mod >>= flip (go D.empty) αs0
   where
   alloc_module :: Module a -> WithGraphT s m (Module Vertex)
   alloc_module (Module Nil) = pure (Module Nil)
   alloc_module (Module (Left (VarDef σ e) : ds)) = do
      VarDef σ' e' <- alloc (VarDef σ e)
      Module ds' <- alloc_module (Module ds)
      pure (Module (Left (VarDef σ' e') : ds'))
   alloc_module (Module (Right ρ : ds)) = do
      ρ' <- traverse alloc ρ
      Module ds' <- alloc_module (Module ds)
      pure (Module (Right ρ' : ds'))

   go :: Env Vertex -> Module Vertex -> s Vertex -> WithGraphT s m (Env Vertex)
   go γ' (Module Nil) _ = pure γ'
   go y' (Module (Left (VarDef σ e) : ds)) αs = do
      v <- eval (γ <+> y') e αs
      γ'' × _ × α' <- except $ match v σ
      go (y' <+> γ'') (Module ds) α'
   go γ' (Module (Right ρ : ds)) αs = do
      γ'' <- closeDefs (γ <+> γ') ρ αs
      go (γ' <+> γ'') (Module ds) αs