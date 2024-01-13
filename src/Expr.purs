module Expr where

import Prelude hiding (absurd, top)

import Bind (Var)
import Control.Apply (lift2)
import Data.Either (Either(..))
import Data.Foldable (class Foldable, foldl, foldrDefault, foldMapDefaultL)
import Data.List (List(..), (:), zipWith)
import Data.Newtype (class Newtype, unwrap)
import Data.Set (Set, empty, unions)
import Data.Set (fromFoldable) as S
import Data.Traversable (class Traversable, sequenceDefault, traverse)
import Data.Tuple (snd)
import DataType (Ctr, consistentWith)
import Dict (Dict, keys, asSingletonMap)
import Dict (apply2) as D
import Lattice (class BoundedJoinSemilattice, class Expandable, class JoinSemilattice, Raw, (∨), definedJoin, expand, maybeJoin)
import Util (type (+), type (×), error, shapeMismatch, singleton, (\\), (×), (∪), (≜), (≞))
import Util.Pair (Pair(..))

-- Deviate from POPL paper by having closures depend on originating lambda or letrec
data Expr a
   = Var Var
   | Op Var
   | Int a Int
   | Float a Number
   | Str a String
   | Record a (Dict (Expr a))
   | Dictionary a (List (Pair (Expr a))) -- constructor name Dict borks (import of same name)
   | Constr a Ctr (List (Expr a))
   | Matrix a (Expr a) (Var × Var) (Expr a)
   | Lambda a (Elim a)
   | Project (Expr a) Var
   | App (Expr a) (Expr a)
   | Let (VarDef a) (Expr a)
   | LetRec (RecDefs a) (Expr a)

-- eliminator here is a singleton with null terminal continuation
data VarDef a = VarDef (Elim a) (Expr a)
data RecDefs a = RecDefs a (Dict (Elim a))

data Elim a
   = ElimVar Var (Cont a)
   | ElimConstr (Dict (Cont a))
   | ElimRecord (Set Var) (Cont a)

-- Continuation of an eliminator branch.
data Cont a
   = -- null continuation, used in let bindings/module variable bindings
     ContNone
   | ContExpr (Expr a)
   | ContElim (Elim a)

asElim :: forall a. Cont a -> Elim a
asElim (ContElim σ) = σ
asElim _ = error "Eliminator expected"

asExpr :: forall a. Cont a -> Expr a
asExpr (ContExpr e) = e
asExpr _ = error "Expression expected"

newtype Module a = Module (List (VarDef a + RecDefs a))

class FV a where
   fv :: a -> Set Var

instance FV (Expr a) where
   fv (Var x) = singleton x
   fv (Op op) = singleton op
   fv (Int _ _) = empty
   fv (Float _ _) = empty
   fv (Str _ _) = empty
   fv (Record _ xes) = unions (fv <$> xes)
   fv (Dictionary _ ees) = unions ((\(Pair e e') -> fv e ∪ fv e') <$> ees)
   fv (Constr _ _ es) = unions (fv <$> es)
   fv (Matrix _ e1 _ e2) = fv e1 ∪ fv e2
   fv (Lambda _ σ) = fv σ
   fv (Project e _) = fv e
   fv (App e1 e2) = fv e1 ∪ fv e2
   fv (Let def e) = fv def ∪ (fv e \\ bv def)
   fv (LetRec ρ e) = fv ρ ∪ fv e

instance FV (Elim a) where
   fv (ElimVar x κ) = fv κ \\ singleton x
   fv (ElimConstr m) = unions (fv <$> m)
   fv (ElimRecord _ κ) = fv κ

instance FV (Cont a) where
   fv ContNone = empty
   fv (ContElim σ) = fv σ
   fv (ContExpr e) = fv e

instance FV (VarDef a) where
   fv (VarDef _ e) = fv e

instance FV (RecDefs a) where
   fv (RecDefs _ ρ) = fv ρ

instance FV a => FV (Dict a) where
   fv ρ = unions (fv <$> ρ) \\ S.fromFoldable (keys ρ)

instance (FV a, FV b) => FV (a × b) where
   fv (x × y) = fv x ∪ fv y

class BV a where
   bv :: a -> Set Var

-- Bound variables, defined only for singleton eliminators.
instance BV (Elim a) where
   bv (ElimVar x κ) = singleton x ∪ bv κ
   bv (ElimConstr m) = bv (snd (asSingletonMap m))
   bv (ElimRecord _ κ) = bv κ

instance BV (VarDef a) where
   bv (VarDef σ _) = bv σ

instance BV (Cont a) where
   bv ContNone = empty
   bv (ContElim σ) = bv σ
   bv (ContExpr _) = empty

instance JoinSemilattice a => JoinSemilattice (Elim a) where
   maybeJoin (ElimVar x κ) (ElimVar x' κ') = ElimVar <$> (x ≞ x') <*> maybeJoin κ κ'
   maybeJoin (ElimConstr cκs) (ElimConstr cκs') =
      ElimConstr <$> ((keys cκs `consistentWith` keys cκs') *> maybeJoin cκs cκs')
   maybeJoin (ElimRecord xs κ) (ElimRecord ys κ') = ElimRecord <$> (xs ≞ ys) <*> maybeJoin κ κ'
   maybeJoin _ _ = shapeMismatch unit

   join σ = definedJoin σ

instance BoundedJoinSemilattice a => Expandable (Elim a) (Raw Elim) where
   expand (ElimVar x κ) (ElimVar x' κ') = ElimVar (x ≜ x') (expand κ κ')
   expand (ElimConstr cκs) (ElimConstr cκs') = ElimConstr (expand cκs cκs')
   expand (ElimRecord xs κ) (ElimRecord ys κ') = ElimRecord (xs ≜ ys) (expand κ κ')
   expand _ _ = shapeMismatch unit

instance JoinSemilattice a => JoinSemilattice (Cont a) where
   maybeJoin ContNone ContNone = pure ContNone
   maybeJoin (ContExpr e) (ContExpr e') = ContExpr <$> maybeJoin e e'
   maybeJoin (ContElim σ) (ContElim σ') = ContElim <$> maybeJoin σ σ'
   maybeJoin _ _ = shapeMismatch unit

   join κ = definedJoin κ

instance BoundedJoinSemilattice a => Expandable (Cont a) (Raw Cont) where
   expand ContNone ContNone = ContNone
   expand (ContExpr e) (ContExpr e') = ContExpr (expand e e')
   expand (ContElim σ) (ContElim σ') = ContElim (expand σ σ')
   expand _ _ = shapeMismatch unit

instance JoinSemilattice a => JoinSemilattice (VarDef a) where
   join def = definedJoin def
   maybeJoin (VarDef σ e) (VarDef σ' e') = VarDef <$> maybeJoin σ σ' <*> maybeJoin e e'

instance BoundedJoinSemilattice a => Expandable (VarDef a) (Raw VarDef) where
   expand (VarDef σ e) (VarDef σ' e') = VarDef (expand σ σ') (expand e e')

instance JoinSemilattice a => JoinSemilattice (RecDefs a) where
   maybeJoin (RecDefs α ρ) (RecDefs α' ρ') = RecDefs (α ∨ α') <$> maybeJoin ρ ρ'
   join ρ = definedJoin ρ

instance BoundedJoinSemilattice a => Expandable (RecDefs a) (Raw RecDefs) where
   expand (RecDefs α ρ) (RecDefs _ ρ') = RecDefs α (expand ρ ρ')

instance JoinSemilattice a => JoinSemilattice (Expr a) where
   maybeJoin (Var x) (Var x') = Var <$> (x ≞ x')
   maybeJoin (Op op) (Op op') = Op <$> (op ≞ op')
   maybeJoin (Int α n) (Int α' n') = Int (α ∨ α') <$> (n ≞ n')
   maybeJoin (Str α str) (Str α' str') = Str (α ∨ α') <$> (str ≞ str')
   maybeJoin (Float α n) (Float α' n') = Float (α ∨ α') <$> (n ≞ n')
   maybeJoin (Record α xes) (Record α' xes') = Record (α ∨ α') <$> maybeJoin xes xes'
   maybeJoin (Dictionary α ees) (Dictionary α' ees') = Dictionary (α ∨ α') <$> maybeJoin ees ees'
   maybeJoin (Constr α c es) (Constr α' c' es') = Constr (α ∨ α') <$> (c ≞ c') <*> maybeJoin es es'
   maybeJoin (Matrix α e1 (x × y) e2) (Matrix α' e1' (x' × y') e2') =
      Matrix (α ∨ α') <$> maybeJoin e1 e1' <*> ((x ≞ x') `lift2 (×)` (y ≞ y')) <*> maybeJoin e2 e2'
   maybeJoin (Lambda α σ) (Lambda α' σ') = Lambda (α ∨ α') <$> maybeJoin σ σ'
   maybeJoin (Project e x) (Project e' x') = Project <$> maybeJoin e e' <*> (x ≞ x')
   maybeJoin (App e1 e2) (App e1' e2') = App <$> maybeJoin e1 e1' <*> maybeJoin e2 e2'
   maybeJoin (Let def e) (Let def' e') = Let <$> maybeJoin def def' <*> maybeJoin e e'
   maybeJoin (LetRec ρ e) (LetRec ρ' e') = LetRec <$> maybeJoin ρ ρ' <*> maybeJoin e e'
   maybeJoin _ _ = shapeMismatch unit

   join e = definedJoin e

instance BoundedJoinSemilattice a => Expandable (Expr a) (Raw Expr) where
   expand (Var x) (Var x') = Var (x ≜ x')
   expand (Op op) (Op op') = Op (op ≜ op')
   expand (Int α n) (Int _ n') = Int α (n ≜ n')
   expand (Str α str) (Str _ str') = Str α (str ≜ str')
   expand (Float α n) (Float _ n') = Float α (n ≜ n')
   expand (Record α xes) (Record _ xes') = Record α (expand xes xes')
   expand (Dictionary α ees) (Dictionary _ ees') = Dictionary α (expand ees ees')
   expand (Constr α c es) (Constr _ c' es') = Constr α (c ≜ c') (expand es es')
   expand (Matrix α e1 (x × y) e2) (Matrix _ e1' (x' × y') e2') =
      Matrix α (expand e1 e1') ((x ≜ x') × (y ≜ y')) (expand e2 e2')
   expand (Lambda α σ) (Lambda _ σ') = Lambda α (expand σ σ')
   expand (Project e x) (Project e' x') = Project (expand e e') (x ≜ x')
   expand (App e1 e2) (App e1' e2') = App (expand e1 e1') (expand e2 e2')
   expand (Let def e) (Let def' e') = Let (expand def def') (expand e e')
   expand (LetRec ρ e) (LetRec ρ' e') = LetRec (expand ρ ρ') (expand e e')
   expand _ _ = shapeMismatch unit

-- ======================
-- boilerplate
-- ======================
derive instance Functor VarDef
derive instance Foldable VarDef
derive instance Traversable VarDef
derive instance Functor Cont
derive instance Foldable Cont
derive instance Traversable Cont
derive instance Functor Elim
derive instance Foldable Elim
derive instance Traversable Elim
derive instance Functor Expr
derive instance Foldable Expr
derive instance Traversable Expr
derive instance Functor RecDefs
derive instance Foldable RecDefs
derive instance Traversable RecDefs
derive instance Newtype (Module a) _
derive instance Functor Module

-- For terms of a fixed shape.
instance Apply Expr where
   apply (Var x) (Var x') = Var (x ≜ x')
   apply (Op op) (Op _) = Op op
   apply (Int fα n) (Int α n') = Int (fα α) (n ≜ n')
   apply (Float fα n) (Float α n') = Float (fα α) (n ≜ n')
   apply (Str fα s) (Str α s') = Str (fα α) (s ≜ s')
   apply (Record fα fxes) (Record α xes) = Record (fα α) (fxes `D.apply2` xes)
   apply (Dictionary fα fxes) (Dictionary α xes) = Dictionary (fα α) (zipWith (lift2 (<*>)) fxes xes)
   apply (Constr fα c fes) (Constr α c' es) = Constr (fα α) (c ≜ c') (zipWith (<*>) fes es)
   apply (Matrix fα fe1 (x × y) fe2) (Matrix α e1 (x' × y') e2) =
      Matrix (fα α) (fe1 <*> e1) ((x ≜ x') × (y ≜ y')) (fe2 <*> e2)
   apply (Lambda fα fσ) (Lambda α σ) = Lambda (fα α) (fσ <*> σ)
   apply (Project fe x) (Project e _) = Project (fe <*> e) x
   apply (App fe1 fe2) (App e1 e2) = App (fe1 <*> e1) (fe2 <*> e2)
   apply (Let (VarDef fσ fe1) fe2) (Let (VarDef σ e1) e2) = Let (VarDef (fσ <*> σ) (fe1 <*> e1)) (fe2 <*> e2)
   apply (LetRec fρ fe) (LetRec ρ e) = LetRec (fρ <*> ρ) (fe <*> e)
   apply _ _ = shapeMismatch unit

instance Apply Elim where
   apply (ElimVar x fk) (ElimVar _ k) = ElimVar x (fk <*> k)
   apply (ElimConstr fk) (ElimConstr k) = ElimConstr (fk `D.apply2` k)
   apply (ElimRecord xs fk) (ElimRecord _ k) = ElimRecord xs (fk <*> k)
   apply _ _ = shapeMismatch unit

instance Apply Cont where
   apply ContNone ContNone = ContNone
   apply (ContExpr f) (ContExpr e) = ContExpr (f <*> e)
   apply (ContElim fσ) (ContElim σ) = ContElim (fσ <*> σ)
   apply _ _ = shapeMismatch unit

instance Apply VarDef where
   apply (VarDef fσ fe) (VarDef σ e) = VarDef (fσ <*> σ) (fe <*> e)

instance Apply RecDefs where
   apply (RecDefs fα fρ) (RecDefs α ρ) = RecDefs (fα α) (fρ `D.apply2` ρ)

-- Apply instance for Either no good here as doesn't assume fixed shape.
instance Apply Module where
   apply (Module Nil) (Module Nil) = Module Nil
   apply (Module (Left fdef : fdefs)) (Module (Left def : defs)) =
      Module (Left (fdef <*> def) : unwrap (apply (Module fdefs) (Module defs)))
   apply (Module (Right fdef : fdefs)) (Module (Right def : defs)) =
      Module (Right (fdef <*> def) : unwrap (apply (Module fdefs) (Module defs)))
   apply _ _ = shapeMismatch unit

-- Foldable instance for Either only considers Right case.
foldlModuleDef :: forall a b. (b -> a -> b) -> b -> VarDef a + RecDefs a -> b
foldlModuleDef f acc (Left def) = foldl f acc def
foldlModuleDef f acc (Right def) = foldl f acc def

instance Foldable Module where
   foldl _ acc (Module Nil) = acc
   foldl f acc (Module (Left def : defs)) =
      foldl (foldlModuleDef f) (foldl f acc def) defs
   foldl f acc (Module (Right def : defs)) =
      foldl (foldlModuleDef f) (foldl f acc def) defs

   foldr f = foldrDefault f
   foldMap f = foldMapDefaultL f

instance Traversable Module where
   traverse _ (Module Nil) = pure (Module Nil)
   traverse f (Module (Left def : ds)) =
      Module <$> ((Left <$> traverse f def) `lift2 (:)` (unwrap <$> traverse f (Module ds)))
   traverse f (Module (Right def : ds)) =
      Module <$> ((Right <$> traverse f def) `lift2 (:)` (unwrap <$> traverse f (Module ds)))

   sequence = sequenceDefault

derive instance Eq a => Eq (Expr a)
derive instance Eq a => Eq (Elim a)
derive instance Eq a => Eq (Cont a)
derive instance Eq a => Eq (VarDef a)
derive instance Eq a => Eq (RecDefs a)

derive instance Ord a => Ord (Expr a)
derive instance Ord a => Ord (Elim a)
derive instance Ord a => Ord (Cont a)
derive instance Ord a => Ord (VarDef a)
derive instance Ord a => Ord (RecDefs a)
