module Eval where

import Prelude hiding (absurd)

import Data.Array (fromFoldable) as A
import Data.Bifunctor (bimap)
import Data.Either (Either(..), note)
import Data.List (List(..), (:), length, range, singleton, unzip, zip)
import Data.Map (lookup)
import Data.Map (keys) as M
import Data.Profunctor.Strong (second)
import Data.Set (union, subset)
import Data.Set (fromFoldable, toUnfoldable) as S
import Data.Traversable (sequence, traverse)
import Data.Tuple (fst, snd)
import Foreign.Object (empty, keys)
import Foreign.Object (fromFoldable, singleton) as O
import Bindings (varAnon)
import DataType (Ctr, arity, consistentCtrs, cPair, dataTypeFor, showCtr)
import Expr (Cont(..), Elim(..), Expr(..), Module(..), RecDefs, VarDef(..), asExpr, fv)
import Lattice (𝔹)
import Pretty (prettyP)
import Primitive (match) as P
import Trace (Trace(..), VarDef(..)) as T
import Trace (Trace, Match(..))
import Util (MayFail, type (×), (×), absurd, check, disjUnion, error, get, report, successful, with)
import Val (Env, PrimOp(..), (<+>), Val, for, lookup', restrict)
import Val (Val(..)) as V

patternMismatch :: String -> String -> String
patternMismatch s s' = "Pattern mismatch: found " <> s <> ", expected " <> s'

match :: Val 𝔹 -> Elim 𝔹 -> MayFail (Env 𝔹 × Cont 𝔹 × Match 𝔹)
match v (ElimVar x κ)  | x == varAnon    = pure (empty × κ × MatchVarAnon v)
                       | otherwise       = pure (O.singleton x v × κ × MatchVar x v)
match (V.Constr _ c vs) (ElimConstr m) = do
   with "Pattern mismatch" $ consistentCtrs [c] (S.toUnfoldable $ M.keys m)
   κ <- note ("Incomplete patterns: no branch for " <> showCtr c) (lookup c m)
   second (MatchConstr c) <$> matchMany vs κ
match v (ElimConstr m) = do
   d <- dataTypeFor (S.toUnfoldable $ M.keys m :: Array Ctr)
   report $ patternMismatch (prettyP v) (show d)
match (V.Record _ xvs) (ElimRecord xs κ)  = do
   check (subset xs (S.fromFoldable $ keys xvs)) $ patternMismatch (show (keys xvs)) (show xs)
   let xs' = xs # S.toUnfoldable
   second (zip xs' >>> O.fromFoldable >>> MatchRecord) <$> matchMany (xs' <#> flip get xvs) κ
match v (ElimRecord xs _) = report (patternMismatch (prettyP v) (show xs))

matchMany :: List (Val 𝔹) -> Cont 𝔹 -> MayFail (Env 𝔹 × Cont 𝔹 × List (Match 𝔹))
matchMany Nil κ = pure (empty × κ × Nil)
matchMany (v : vs) (ContElim σ) = do
   γ  × κ'  × w  <- match v σ
   γ' × κ'' × ws <- matchMany vs κ'
   pure $ γ `disjUnion` γ' × κ'' × (w : ws)
matchMany (_ : vs) (ContExpr _) = report $
   show (length vs + 1) <> " extra argument(s) to constructor/record; did you forget parentheses in lambda pattern?"
matchMany _ _ = error absurd

closeDefs :: Env 𝔹 -> RecDefs 𝔹 -> Env 𝔹
closeDefs γ ρ = ρ <#> \σ ->
   let xs = fv (ρ `for` σ) `union` fv σ
   in V.Closure false (γ `restrict` xs) ρ σ

checkArity :: Ctr -> Int -> MayFail Unit
checkArity c n = do
   n' <- arity c
   check (n' >= n) (showCtr c <> " got " <> show n <> " argument(s), expects at most " <> show n')

eval :: Env 𝔹 -> Expr 𝔹 -> MayFail (Trace 𝔹 × Val 𝔹)
eval γ (Var x)       = (T.Var x × _) <$> lookup' x γ
eval γ (Op op)       = (T.Op op × _) <$> lookup' op γ
eval _ (Int _ n)     = pure (T.Int n × V.Int false n)
eval _ (Float _ n)   = pure (T.Float n × V.Float false n)
eval _ (Str _ str)   = pure (T.Str str × V.Str false str)
eval γ (Record _ xes) = do
   xtvs <- traverse (eval γ) xes
   pure $ (T.Record $ xtvs <#> fst) × V.Record false (xtvs <#> snd)
eval γ (Constr _ c es) = do
   checkArity c (length es)
   ts × vs <- traverse (eval γ) es <#> unzip
   pure (T.Constr c ts × V.Constr false c vs)
eval γ (Matrix _ e (x × y) e') = do
   t × v <- eval γ e'
   case v of
      V.Constr _ c (v1 : v2 : Nil) | c == cPair -> do
         let (i' × _) × (j' × _) = P.match v1 × P.match v2
         check (i' × j' >= 1 × 1) ("array must be at least (" <> show (1 × 1) <> "); got (" <> show (i' × j') <> ")")
         tss × vss <- unzipToArray <$> ((<$>) unzipToArray) <$> (sequence $ do
            i <- range 1 i'
            singleton $ sequence $ do
               j <- range 1 j'
               let γ' = O.singleton x (V.Int false i) `disjUnion` (O.singleton y (V.Int false j))
               singleton (eval (γ <+> γ') e))
         pure (T.Matrix tss (x × y) (i' × j') t × V.Matrix false (vss × (i' × false) × (j' × false)))
      v' -> report ("Array dimensions must be pair of ints; got " <> prettyP v')
   where
   unzipToArray :: forall a b . List (a × b) -> Array a × Array b
   unzipToArray = unzip >>> bimap A.fromFoldable A.fromFoldable
eval γ (Lambda σ) =
   pure (T.Lambda σ × V.Closure false (γ `restrict` fv σ) empty σ)
eval γ (Project e x) = do
   t × v <- eval γ e
   case v of
      V.Record _ xvs -> (T.Project t x × _) <$> lookup' x xvs
      _ -> report "Expected record"
eval γ (App e e') = do
   t × v <- eval γ e
   t' × v' <- eval γ e'
   case v of
      V.Closure _ γ1 ρ σ -> do
         let γ2 = closeDefs γ1 ρ
         γ3 × e'' × w <- match v' σ
         t'' × v'' <- eval (γ1 <+> γ2 <+> γ3) (asExpr e'')
         pure (T.App (t × S.fromFoldable (keys ρ) × σ) t' w t'' × v'')
      V.Primitive (PrimOp φ) vs ->
         let vs' = vs <> singleton v'
             v'' = if φ.arity > length vs' then V.Primitive (PrimOp φ) vs' else φ.op vs' in
         pure (T.AppPrim (t × PrimOp φ × vs) (t' × v') × v'')
      V.Constr _ c vs -> do
         check (successful (arity c) > length vs) ("Too many arguments to " <> showCtr c)
         pure (T.AppConstr (t × c × length vs) t' × V.Constr false c (vs <> singleton v'))
      _ -> report "Expected closure, operator or unsaturated constructor"
eval γ (Let (VarDef σ e) e') = do
   t × v <- eval γ e
   γ' × _ × w <- match v σ -- terminal meta-type of eliminator is meta-unit
   t' × v' <- eval (γ <+> γ') e'
   pure (T.Let (T.VarDef w t) t' × v')
eval γ (LetRec ρ e) = do
   let γ' = closeDefs γ ρ
   t × v <- eval (γ <+> γ') e
   pure (T.LetRec ρ t × v)

eval_module :: Env 𝔹 -> Module 𝔹 -> MayFail (Env 𝔹)
eval_module γ = go empty
   where
   go :: Env 𝔹 -> Module 𝔹 -> MayFail (Env 𝔹)
   go γ' (Module Nil) = pure γ'
   go y' (Module (Left (VarDef σ e) : ds)) = do
      _  × v <- eval (γ <+> y') e
      γ'' × _ × _  <- match v σ
      go (y' <+> γ'') (Module ds)
   go γ' (Module (Right ρ : ds)) =
      go (γ' <+> closeDefs (γ <+> γ') ρ) (Module ds)
