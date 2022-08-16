module Expr2 where

import Prelude hiding (absurd, top)
import Control.Apply (lift2)
import Data.List (List(..), (:))
import Data.Map (Map)
import Data.Set (Set, difference, empty, intersection, member, singleton, toUnfoldable, union, unions)
import Data.Tuple (snd)
import Bindings2 (Bindings, Var, dom, find, val)
import DataType2 (Ctr)
import Lattice2 (class BoundedSlices, class JoinSemilattice, class Slices, (∨), bot, botOf, definedJoin, maybeJoin, neg)
import Util2 (Endo, type (×), (×), type (+), (≞), asSingletonMap, error, report, successful)
import Util.SnocList2 (SnocList)

data Expr a =
   Var Var |
   Op Var |
   Int a Int |
   Float a Number |
   Str a String |
   Record a (Bindings (Expr a)) |
   Constr a Ctr (List (Expr a)) |
   Matrix a (Expr a) (Var × Var) (Expr a) |
   Lambda (Elim a) |
   RecordLookup (Expr a) Var |
   App (Expr a) (Expr a) |
   Let (VarDef a) (Expr a) |
   LetRec (RecDefs a) (Expr a)

-- eliminator here is a singleton with null terminal continuation
data VarDef a = VarDef (Elim a) (Expr a)
type RecDefs a = Bindings (Elim a)

reaches :: forall a . RecDefs a -> Endo (Set Var)
reaches ρ xs = go (toUnfoldable xs) empty
   where
   dom_ρ = dom ρ
   go :: List Var -> Endo (Set Var)
   go Nil acc                          = acc
   go (x : xs') acc | x `member` acc   = go xs' acc
   go (x : xs') acc | otherwise        =
      let σ = successful $ find x ρ in
      go (toUnfoldable (fv σ `intersection` dom_ρ) <> xs')
         (singleton x `union` acc)

data Elim a =
   ElimVar Var (Cont a) |
   ElimConstr (Map Ctr (Cont a)) |
   ElimRecord (SnocList Var) (Cont a)

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
   fv (Op _)               = empty
   fv (Int _ _)            = empty
   fv (Float _ _)          = empty
   fv (Str _ _)            = empty
   fv (Record _ xes)       = unions (fv <$> val <$> xes)
   fv (Constr _ _ es)      = unions (fv <$> es)
   fv (Matrix _ e1 _ e2)   = union (fv e1) (fv e2)
   fv (Lambda σ)           = fv σ
   fv (RecordLookup e _)   = fv e
   fv (App e1 e2)          = fv e1 `union` fv e2
   fv (Let def e)          = fv def `union` (fv e `difference` bv def)
   fv (LetRec δ e)         = unions (fv <$> val <$> δ) `union` fv e

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

instance FV (RecDefs a) where
   fv ρ = unions $ val <$> ((<$>) fv) <$> ρ

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
   maybeJoin (ElimConstr κs) (ElimConstr κs')      = ElimConstr <$> maybeJoin κs κs'
   maybeJoin (ElimRecord xs κ) (ElimRecord ys κ')  = ElimRecord <$> (xs ≞ ys) <*> maybeJoin κ κ'
   maybeJoin _ _                                   = report "Incompatible eliminators"

instance BoundedSlices (Elim Boolean) where
   botOf (ElimVar x κ) = ElimVar x (botOf κ)
   botOf (ElimConstr κs) = ElimConstr (botOf <$> κs)
   botOf (ElimRecord xs κ) = ElimRecord xs (botOf κ)

instance JoinSemilattice (Cont Boolean) where
   join = definedJoin
   neg = (<$>) neg

instance Slices (Cont Boolean) where
   maybeJoin (ContExpr e) (ContExpr e')   = ContExpr <$> maybeJoin e e'
   maybeJoin (ContElim σ) (ContElim σ')   = ContElim <$> maybeJoin σ σ'
   maybeJoin _ _                          = report "Incompatible continuations"

instance BoundedSlices (Cont Boolean) where
   botOf ContNone       = ContNone
   botOf (ContExpr e)   = ContExpr (botOf e)
   botOf (ContElim σ)   = ContElim (botOf σ)

instance JoinSemilattice (VarDef Boolean) where
   join = definedJoin
   neg = (<$>) neg

instance Slices (VarDef Boolean) where
   maybeJoin (VarDef σ e) (VarDef σ' e') = VarDef <$> maybeJoin σ σ' <*> maybeJoin e e'

instance BoundedSlices (VarDef Boolean) where
   botOf (VarDef σ e) = VarDef (botOf σ) (botOf e)

instance BoundedSlices (Expr Boolean) where
   botOf (Var x)                    = Var x
   botOf (Op op)                    = Op op
   botOf (Int _ n)                  = Int bot n
   botOf (Str _ str)                = Str bot str
   botOf (Float _ n)                = Float bot n
   botOf (Record _ xes)             = Record bot (botOf xes)
   botOf (Constr _ c es)            = Constr bot c (botOf es)
   botOf (Matrix _ e1 (x × y) e2)   = Matrix bot (botOf e1) (x × y) (botOf e2)
   botOf (Lambda σ)                 = Lambda (botOf σ)
   botOf (RecordLookup e x)         = RecordLookup (botOf e) x
   botOf (App e1 e2)                = App (botOf e1) (botOf e2)
   botOf (Let def e)                = Let (botOf def) (botOf e)
   botOf (LetRec δ e)               = LetRec (botOf δ) (botOf e)

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
   maybeJoin (RecordLookup e x) (RecordLookup e' x')            = RecordLookup <$> maybeJoin e e' <*> (x ≞ x')
   maybeJoin (App e1 e2) (App e1' e2')                         = App <$> maybeJoin e1 e1' <*> maybeJoin e2 e2'
   maybeJoin (Let def e) (Let def' e')                         = Let <$> maybeJoin def def' <*> maybeJoin e e'
   maybeJoin (LetRec δ e) (LetRec δ' e')                       = LetRec <$> maybeJoin δ δ' <*> maybeJoin e e'
   maybeJoin _ _                                               = report "Incompatible expressions"
