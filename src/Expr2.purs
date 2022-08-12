module Expr2 where

import Prelude hiding (absurd, top)
import Control.Apply (lift2)
import Data.List (List)
import Data.Map (Map)
import Bindings (Bindings, Var, (⪂))
import DataType (Ctr)
import Lattice (
   class BoundedSlices, class Expandable, class JoinSemilattice, class Slices, (∨), bot, botOf, definedJoin, expand, maybeJoin, neg
)
import Util (type (×), (×), type (+), (≞), (≜), (⪄), absurd, error, report)
import Util.SnocList (SnocList)

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

-- eliminator in var def is always singleton, with an empty terminal continuation represented by hole
data VarDef a = VarDef (Elim a) (Expr a)
type RecDefs a = Bindings (Elim a)

data Elim a =
   ElimVar Var (Cont a) |
   ElimConstr (Map Ctr (Cont a)) |
   ElimRecord (SnocList Var) (Cont a)

-- Continuation of an eliminator branch.
data Cont a =
   ContExpr (Expr a) |
   ContElim (Elim a)

asElim :: forall a . Cont a -> Elim a
asElim (ContElim σ)  = σ
asElim (ContExpr _)  = error "Eliminator expected"

asExpr :: forall a . Cont a -> Expr a
asExpr (ContElim _)  = error "Expression expected"
asExpr (ContExpr e)  = e

data Module a = Module (List (VarDef a + RecDefs a))

-- ======================
-- boilerplate
-- ======================
derive instance functorVarDef :: Functor VarDef
derive instance functorExpr :: Functor Expr
derive instance functorCont :: Functor Cont
derive instance functorElim :: Functor Elim

instance joinSemilatticeElim :: JoinSemilattice (Elim Boolean) where
   join = definedJoin
   neg = (<$>) neg

instance slicesElim :: Slices (Elim Boolean) where
   maybeJoin (ElimVar x κ) (ElimVar x' κ')         = ElimVar <$> (x ≞ x') <*> maybeJoin κ κ'
   maybeJoin (ElimConstr κs) (ElimConstr κs')      = ElimConstr <$> maybeJoin κs κs'
   maybeJoin (ElimRecord xs κ) (ElimRecord ys κ')  = ElimRecord <$> (xs ≞ ys) <*> maybeJoin κ κ'
   maybeJoin _ _                                   = report "Incompatible eliminators"

instance boundedSlicesElim :: BoundedSlices (Elim Boolean) where
   botOf = ?_

instance joinSemilatticeCont :: JoinSemilattice (Cont Boolean) where
   join = definedJoin
   neg = (<$>) neg

instance slicesCont :: Slices (Cont Boolean) where
   maybeJoin (ContExpr e) (ContExpr e')   = ContExpr <$> maybeJoin e e'
   maybeJoin (ContElim σ) (ContElim σ')   = ContElim <$> maybeJoin σ σ'
   maybeJoin _ _                          = report "Incompatible continuations"

instance boundedSlicesCont :: BoundedSlices (Cont Boolean) where
   botOf = ?_

instance joinSemilatticeVarDef :: JoinSemilattice (VarDef Boolean) where
   join = definedJoin
   neg = (<$>) neg

instance slicesVarDef :: Slices (VarDef Boolean) where
   maybeJoin (VarDef σ e) (VarDef σ' e') = VarDef <$> maybeJoin σ σ' <*> maybeJoin e e'

instance boundedSlicesExpr :: BoundedSlices (Expr Boolean) where
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

instance joinSemilatticeExpr :: JoinSemilattice (Expr Boolean) where
   join = definedJoin
   neg = (<$>) neg

instance slicesExpr :: Slices (Expr Boolean) where
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
