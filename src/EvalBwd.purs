module EvalBwd where

import Prelude hiding (absurd)
import Data.Foldable (foldr, length)
import Data.FoldableWithIndex (foldrWithIndex)
import Data.List (List(..), (:), range, reverse, unsnoc, unzip, zip)
import Data.List (singleton) as L
import Data.List.NonEmpty (NonEmptyList(..))
import Data.NonEmpty (foldl1)
import Data.Set (union)
import Data.Set (fromFoldable, singleton) as S
import Data.Tuple (fst, snd, uncurry)
import Partial.Unsafe (unsafePartial)
import Bindings (Var, varAnon)
import DataType (cPair)
import Dict (disjointUnion, disjointUnion_inv, empty, get, insert, intersectionWith, isEmpty, keys)
import Dict (fromFoldable, singleton, toUnfoldable) as D
import Expr (Cont(..), Elim(..), Expr(..), RecDefs, VarDef(..), bv)
import Lattice (𝔹, (∨), bot, botOf, expand)
import Trace (Trace(..), VarDef(..)) as T
import Trace (Trace, Match(..))
import Util (Endo, type (×), (×), (!), absurd, error, definitely', nonEmpty)
import Val (Env, PrimOp(..), (<+>), Val, append_inv)
import Val (Val(..)) as V

closeDefsBwd :: Env 𝔹 -> Env 𝔹 × RecDefs 𝔹 × 𝔹
closeDefsBwd γ =
   case foldrWithIndex joinDefs (empty × empty × empty × false) γ of
      ρ' × γ' × ρ × α -> γ' × (ρ ∨ ρ') × α
   where
   joinDefs :: Var -> Val 𝔹 -> Endo (RecDefs 𝔹 × Env 𝔹 × RecDefs 𝔹 × 𝔹)
   joinDefs f _ (ρ_acc × γ' × ρ × α) =
      case get f γ of
         V.Closure α_f γ_f ρ_f σ_f ->
            (ρ_acc # insert f σ_f) × (γ' ∨ γ_f) × (ρ ∨ ρ_f) × (α ∨ α_f)
         _ -> error absurd

matchBwd :: Env 𝔹 -> Cont 𝔹 -> 𝔹 -> Match 𝔹 -> Val 𝔹 × Elim 𝔹
matchBwd γ κ _ (MatchVar x v)
   | keys γ == S.singleton x = get x γ × ElimVar x κ
   | otherwise = botOf v × ElimVar x κ
matchBwd γ κ _ (MatchVarAnon v)
   | isEmpty γ = botOf v × ElimVar varAnon κ
   | otherwise = error absurd
matchBwd ρ κ α (MatchConstr c ws) = V.Constr α c vs × ElimConstr (D.singleton c κ')
   where
   vs × κ' = matchManyBwd ρ κ α (reverse ws)
matchBwd ρ κ α (MatchRecord xws) = V.Record α (zip xs vs # D.fromFoldable) ×
   ElimRecord (S.fromFoldable $ keys xws) κ'
   where
   xs × ws = xws # D.toUnfoldable # unzip
   vs × κ' = matchManyBwd ρ κ α (ws # reverse)

matchManyBwd :: Env 𝔹 -> Cont 𝔹 -> 𝔹 -> List (Match 𝔹) -> List (Val 𝔹) × Cont 𝔹
matchManyBwd γ κ _ Nil
   | isEmpty γ = Nil × κ
   | otherwise = error absurd
matchManyBwd γγ' κ α (w : ws) =
   (vs <> v : Nil) × κ'
   where
   γ × γ' = disjointUnion_inv (bv w) γγ'
   v × σ = matchBwd γ κ α w
   vs × κ' = matchManyBwd γ' (ContElim σ) α ws

evalBwd :: Env 𝔹 -> Expr 𝔹 -> Val 𝔹 -> Trace 𝔹 -> Env 𝔹 × Expr 𝔹 × 𝔹
evalBwd γ e v t =
   expand γ' γ × expand e' e × α
   where
   γ' × e' × α = evalBwd' v t

-- Computes a partial slice which evalBwd expands to a full slice.
evalBwd' :: Val 𝔹 -> Trace 𝔹 -> Env 𝔹 × Expr 𝔹 × 𝔹
evalBwd' v (T.Var x) = D.singleton x v × Var x × false
evalBwd' v (T.Op op) = D.singleton op v × Op op × false
evalBwd' (V.Str α _) (T.Str str) = empty × Str α str × α
evalBwd' (V.Int α _) (T.Int n) = empty × Int α n × α
evalBwd' (V.Float α _) (T.Float n) = empty × Float α n × α
evalBwd' (V.Closure α γ _ σ) (T.Lambda _) = γ × Lambda σ × α
evalBwd' (V.Record α xvs) (T.Record xts) =
   γ' × Record α (xγeαs <#> (fst >>> snd)) × (foldr (∨) α (xγeαs <#> snd))
   where
   xvts = intersectionWith (×) xvs xts
   xγeαs = xvts <#> uncurry evalBwd'
   γ' = foldr (∨) empty (xγeαs <#> (fst >>> fst))
evalBwd' (V.Constr α _ vs) (T.Constr c ts) =
   γ' × Constr α c es × α'
   where
   evalArg_bwd :: Val 𝔹 × Trace 𝔹 -> Endo (Env 𝔹 × List (Expr 𝔹) × 𝔹)
   evalArg_bwd (v' × t') (γ' × es × α') = (γ' ∨ γ'') × (e : es) × (α' ∨ α'')
      where
      γ'' × e × α'' = evalBwd' v' t'
   γ' × es × α' = foldr evalArg_bwd (empty × Nil × α) (zip vs ts)
evalBwd' (V.Matrix α (vss × (_ × βi) × (_ × βj))) (T.Matrix tss (x × y) (i' × j') t') =
   (γ ∨ γ') × Matrix α e (x × y) e' × (α ∨ α' ∨ α'')
   where
   NonEmptyList ijs = nonEmpty $ do
      i <- range 1 i'
      j <- range 1 j'
      L.singleton (i × j)

   evalBwd_elem :: (Int × Int) -> Env 𝔹 × Expr 𝔹 × 𝔹 × 𝔹 × 𝔹
   evalBwd_elem (i × j) =
      case evalBwd' (vss ! (i - 1) ! (j - 1)) (tss ! (i - 1) ! (j - 1)) of
         γ'' × e × α' ->
            unsafePartial $ γ × e × α' × β × β'
            where
            V.Int β _ × V.Int β' _ = get x γ0 × get x γ0
            γ × γ' = append_inv (S.singleton x `union` S.singleton y) γ''
            γ0 = (D.singleton x (V.Int bot i') `disjointUnion` D.singleton y (V.Int bot j')) <+> γ'
   γ × e × α' × β × β' = foldl1
      ( \(γ1 × e1 × α1 × β1 × β1') (γ2 × e2 × α2 × β2 × β2') ->
           ((γ1 ∨ γ2) × (e1 ∨ e2) × (α1 ∨ α2) × (β1 ∨ β2) × (β1' ∨ β2'))
      )
      (evalBwd_elem <$> ijs)
   γ' × e' × α'' = evalBwd' (V.Constr false cPair (V.Int (β ∨ βi) i' : V.Int (β' ∨ βj) j' : Nil)) t'
evalBwd' v (T.Project t x) =
   ρ × Project e x × α
   where
   ρ × e × α = evalBwd' (V.Record false (D.singleton x v)) t
evalBwd' v (T.App (t1 × xs × _) t2 w t3) =
   (γ' ∨ γ'') × App e1 e2 × (α ∨ α')
   where
   γ1γ2γ3 × e × β = evalBwd' v t3
   γ1γ2 × γ3 = append_inv (bv w) γ1γ2γ3
   v' × σ = matchBwd γ3 (ContExpr e) β w
   γ1 × γ2 = append_inv xs γ1γ2
   γ' × e2 × α = evalBwd' v' t2
   γ1' × δ' × β' = closeDefsBwd γ2
   γ'' × e1 × α' = evalBwd' (V.Closure (β ∨ β') (γ1 ∨ γ1') δ' σ) t1
evalBwd' v (T.AppPrim (t1 × PrimOp φ × vs) (t2 × v2)) =
   (γ ∨ γ') × App e e' × (α ∨ α')
   where
   vs' = vs <> L.singleton v2
   { init: vs'', last: v2' } = definitely' $ unsnoc $
      if φ.arity > length vs' then unsafePartial $ let V.Primitive _ vs'' = v in vs''
      else φ.op_bwd v vs'
   γ × e × α = evalBwd' (V.Primitive (PrimOp φ) vs'') t1
   γ' × e' × α' = evalBwd' v2' t2
evalBwd' (V.Constr β _ vs) (T.AppConstr (t1 × c × _) t2) =
   (γ ∨ γ') × App e e' × (α ∨ α')
   where
   { init: vs', last: v2 } = definitely' (unsnoc vs)
   γ × e × α = evalBwd' (V.Constr β c vs') t1
   γ' × e' × α' = evalBwd' v2 t2
evalBwd' v (T.Let (T.VarDef w t1) t2) =
   (γ1 ∨ γ1') × Let (VarDef σ e1) e2 × (α1 ∨ α2)
   where
   γ1γ2 × e2 × α2 = evalBwd' v t2
   γ1 × γ2 = append_inv (bv w) γ1γ2
   v' × σ = matchBwd γ2 ContNone α2 w
   γ1' × e1 × α1 = evalBwd' v' t1
evalBwd' v (T.LetRec ρ t) =
   (γ1 ∨ γ1') × LetRec ρ' e × (α ∨ α')
   where
   γ1γ2 × e × α = evalBwd' v t
   γ1 × γ2 = append_inv (S.fromFoldable $ keys ρ) γ1γ2
   γ1' × ρ' × α' = closeDefsBwd γ2
evalBwd' _ _ = error absurd
