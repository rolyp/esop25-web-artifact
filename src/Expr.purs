module Expr where

import Prelude hiding (absurd, top)
import Control.Apply (lift2)
import Data.List (List)
import Data.Map (Map)
import Data.Map (keys) as M
import Data.Set (Set, difference, empty, singleton, union, unions)
import Data.Set (fromFoldable, toUnfoldable) as S
import Data.Tuple (snd)
import Foreign.Object (keys)
import Bindings (Dict, Var)
import DataType (Ctr, consistentCtrs)
import Lattice (class Expandable, class JoinSemilattice, class Slices, (∨), definedJoin, expand, maybeJoin, neg)
import Util (type (×), (×), type (+), (≜), (≞), asSingletonMap, error, report)

data Expr a =
   Var Var |
   Op Var |
   Int a Int |
   Float a Number |
   Str a String |
   Record a (Dict (Expr a)) |
   Constr a Ctr (List (Expr a)) |
   Matrix a (Expr a) (Var × Var) (Expr a) |
   Lambda (Elim a) |
   Project (Expr a) Var |
   App (Expr a) (Expr a) |
   Let (VarDef a) (Expr a) |
   LetRec (RecDefs a) (Expr a)

-- eliminator here is a singleton with null terminal continuation
data VarDef a = VarDef (Elim a) (Expr a)
type RecDefs a = Dict (Elim a)

data Elim a =
   ElimVar Var (Cont a) |
   ElimConstr (Map Ctr (Cont a)) |
   ElimRecord (Set Var) (Cont a)

-- Continuation of an eliminator branch.
data Cont a =
   ContNone |           -- null continuation, used in let bindings/module variable bindings
   ContExpr (Expr a) |
   ContElim (Elim a)

asElim :: forall a . Cont a -> Elim a
asElim (ContElim σ)  = σ
asElim _             = error "Eliminator expected"

asExpr :: forall a . Cont a -> Expr a
asExpr (ContExpr e)  = e
asExpr _             = error "Expression expected"

data Module a = Module (List (VarDef a + RecDefs a))

class FV a where
   fv :: a -> Set Var

instance FV (Expr a) where
   fv (Var x)              = singleton x
   fv (Op op)              = singleton op
   fv (Int _ _)            = empty
   fv (Float _ _)          = empty
   fv (Str _ _)            = empty
   fv (Record _ xes)       = unions (fv <$> xes)
   fv (Constr _ _ es)      = unions (fv <$> es)
   fv (Matrix _ e1 _ e2)   = union (fv e1) (fv e2)
   fv (Lambda σ)           = fv σ
   fv (Project e _)   = fv e
   fv (App e1 e2)          = fv e1 `union` fv e2
   fv (Let def e)          = fv def `union` (fv e `difference` bv def)
   fv (LetRec ρ e)         = unions (fv <$> ρ) `union` fv e

instance FV (Elim a) where
   fv (ElimVar x κ)     = fv κ `difference` singleton x
   fv (ElimConstr m)    = unions (fv <$> m)
   fv (ElimRecord _ κ)  = fv κ

instance FV (Cont a) where
   fv ContNone       = empty
   fv (ContElim σ)   = fv σ
   fv (ContExpr e)   = fv e

instance FV (VarDef a) where
   fv (VarDef _ e) = fv e

instance FV a => FV (Dict a) where
   fv ρ = (unions $ (fv <$> ρ)) `difference` (S.fromFoldable $ keys ρ)

class BV a where
   bv :: a -> Set Var

-- Bound variables, defined only for singleton eliminators.
instance BV (Elim a) where
   bv (ElimVar x κ)     = singleton x `union` bv κ
   bv (ElimConstr m)    = bv (snd (asSingletonMap m))
   bv (ElimRecord _ κ) = bv κ

instance BV (VarDef a) where
   bv (VarDef σ _) = bv σ

instance BV (Cont a) where
   bv ContNone       = empty
   bv (ContElim σ)   = bv σ
   bv (ContExpr _)   = empty

-- ======================
-- boilerplate
-- ======================
derive instance Functor VarDef
derive instance Functor Expr
derive instance Functor Cont
derive instance Functor Elim

instance JoinSemilattice (Elim Boolean) where
   join = definedJoin
   neg = (<$>) neg

instance Slices (Elim Boolean) where
   maybeJoin (ElimVar x κ) (ElimVar x' κ')         = ElimVar <$> (x ≞ x') <*> maybeJoin κ κ'
   maybeJoin (ElimConstr cκs) (ElimConstr cκs')    =
      ElimConstr <$> (consistentCtrs (S.toUnfoldable $ M.keys cκs) (S.toUnfoldable $ M.keys cκs')
                     *> maybeJoin cκs cκs')
   maybeJoin (ElimRecord xs κ) (ElimRecord ys κ')  = ElimRecord <$> (xs ≞ ys) <*> maybeJoin κ κ'
   maybeJoin _ _                                   = report "Incompatible eliminators"

instance Expandable (Elim Boolean) where
   expand (ElimVar x κ) (ElimVar x' κ')         = ElimVar (x ≜ x') (expand κ κ')
   expand (ElimConstr cκs) (ElimConstr cκs')    = ElimConstr (expand cκs cκs')
   expand (ElimRecord xs κ) (ElimRecord ys κ')  = ElimRecord (xs ≜ ys) (expand κ κ')
   expand _ _                                   = error "Incompatible eliminators"

instance JoinSemilattice (Cont Boolean) where
   join = definedJoin
   neg = (<$>) neg

instance Slices (Cont Boolean) where
   maybeJoin ContNone ContNone            = pure ContNone
   maybeJoin (ContExpr e) (ContExpr e')   = ContExpr <$> maybeJoin e e'
   maybeJoin (ContElim σ) (ContElim σ')   = ContElim <$> maybeJoin σ σ'
   maybeJoin _ _                          = report "Incompatible continuations"

instance Expandable (Cont Boolean) where
   expand ContNone ContNone            = ContNone
   expand (ContExpr e) (ContExpr e')   = ContExpr (expand e e')
   expand (ContElim σ) (ContElim σ')   = ContElim (expand σ σ')
   expand _ _                          = error "Incompatible continuations"

instance JoinSemilattice (VarDef Boolean) where
   join = definedJoin
   neg = (<$>) neg

instance Slices (VarDef Boolean) where
   maybeJoin (VarDef σ e) (VarDef σ' e') = VarDef <$> maybeJoin σ σ' <*> maybeJoin e e'

instance Expandable (VarDef Boolean) where
   expand (VarDef σ e) (VarDef σ' e') = VarDef (expand σ σ') (expand e e')

instance JoinSemilattice (Expr Boolean) where
   join = definedJoin
   neg = (<$>) neg

instance Slices (Expr Boolean) where
   maybeJoin (Var x) (Var x')                                  = Var <$> (x ≞ x')
   maybeJoin (Op op) (Op op')                                  = Op <$> (op ≞ op')
   maybeJoin (Int α n) (Int α' n')                             = Int (α ∨ α') <$> (n ≞ n')
   maybeJoin (Str α str) (Str α' str')                         = Str (α ∨ α') <$> (str ≞ str')
   maybeJoin (Float α n) (Float α' n')                         = Float (α ∨ α') <$> (n ≞ n')
   maybeJoin (Record α xes) (Record α' xes')                   = Record (α ∨ α') <$> maybeJoin xes xes'
   maybeJoin (Constr α c es) (Constr α' c' es')                = Constr (α ∨ α') <$> (c ≞ c') <*> maybeJoin es es'
   maybeJoin (Matrix α e1 (x × y) e2) (Matrix α' e1' (x' × y') e2') =
      Matrix (α ∨ α') <$> maybeJoin e1 e1' <*> ((x ≞ x') `lift2 (×)` (y ≞ y')) <*> maybeJoin e2 e2'
   maybeJoin (Lambda σ) (Lambda σ')                            = Lambda <$> maybeJoin σ σ'
   maybeJoin (Project e x) (Project e' x')                     = Project <$> maybeJoin e e' <*> (x ≞ x')
   maybeJoin (App e1 e2) (App e1' e2')                         = App <$> maybeJoin e1 e1' <*> maybeJoin e2 e2'
   maybeJoin (Let def e) (Let def' e')                         = Let <$> maybeJoin def def' <*> maybeJoin e e'
   maybeJoin (LetRec ρ e) (LetRec ρ' e')                       = LetRec <$> maybeJoin ρ ρ' <*> maybeJoin e e'
   maybeJoin _ _                                               = report "Incompatible expressions"

instance Expandable (Expr Boolean) where
   expand (Var x) (Var x')                                  = Var (x ≜ x')
   expand (Op op) (Op op')                                  = Op (op ≜ op')
   expand (Int α n) (Int _ n')                              = Int α (n ≜ n')
   expand (Str α str) (Str _ str')                          = Str α (str ≜ str')
   expand (Float α n) (Float _ n')                          = Float α (n ≜ n')
   expand (Record α xes) (Record _ xes')                    = Record α (expand xes xes')
   expand (Constr α c es) (Constr _ c' es')                 = Constr α (c ≜ c') (expand es es')
   expand (Matrix α e1 (x × y) e2) (Matrix _ e1' (x' × y') e2') =
      Matrix α (expand e1 e1') ((x ≜ x') × (y ≜ y')) (expand e2 e2')
   expand (Lambda σ) (Lambda σ')                            = Lambda (expand σ σ')
   expand (Project e x) (Project e' x')                     = Project (expand e e') (x ≜ x')
   expand (App e1 e2) (App e1' e2')                         = App (expand e1 e1') (expand e2 e2')
   expand (Let def e) (Let def' e')                         = Let (expand def def') (expand e e')
   expand (LetRec ρ e) (LetRec ρ' e')                       = LetRec (expand ρ ρ') (expand e e')
   expand _ _                                               = error "Incompatible expressions"
