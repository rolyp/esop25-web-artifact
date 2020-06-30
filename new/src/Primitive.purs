module Primitive where

import Prelude hiding (apply, append, map)
import Prelude (map) as P
import Data.Foldable (foldl)
import Data.List (List(..), (:))
import Data.List as L
import Data.Map (Map, fromFoldable)
import Text.Parsing.Parser.Expr (Assoc(..))
import Bindings (Bindings(..), Var, (:+:), (↦))
import DataType (cTrue, cFalse, Ctr(..))
import Lattice (Selected, (∧))
import Util (type (×), (×), error)
import Expr as E
import Expr (Expr(..), Elim, expr)
import Val (Binary(..), BinaryOp(..), Env, Unary(..), UnaryOp(..), Val(..), val)
import Val (RawVal(..)) as V

-- name in user land, precedence 0 to 9 (similar to Haskell 98), associativity
type OpDef = {
   op    :: Var,
   prec  :: Int,
   assoc :: Assoc
}

opDef :: Var -> Int -> Assoc -> Var × OpDef
opDef op prec assoc = op × { op, prec, assoc }

-- Syntactic information only. No guarantee that any of these will be defined.
opDefs :: Map String OpDef
opDefs = fromFoldable [
   opDef "*"   7 AssocLeft,
   opDef "+"   6 AssocLeft,
   opDef "-"   6 AssocLeft,
   opDef ":"   6 AssocRight,
   opDef "=="  4 AssocNone,
   opDef "/="  4 AssocNone,
   opDef "<"   4 AssocLeft,
   opDef ">"   4 AssocLeft,
   opDef "<="  4 AssocLeft,
   opDef ">="  4 AssocLeft
]

-- Enforce argument type requirements.
class ToList a where
   toList :: a -> List a

class FromList a where
   fromList :: List a -> a

instance exprToList :: ToList Expr where
   toList (Expr a (E.Constr (Ctr "Cons") (e:es:Nil))) = (e:toList es)
   toList (Expr a (E.Constr (Ctr "Nil") Nil)) = Nil
   toList _ = error "expected list expression"

instance exprFromList :: FromList Expr where
   fromList (x:xs) = expr $ (E.Constr (Ctr "Cons") (x:fromList xs:Nil))
   fromList Nil    = expr $ E.Constr (Ctr "Nil") Nil

class To a where
   to :: Val -> a

class From a where
   from :: a -> Val

instance toInt :: To Int where
   to (Val _ (V.Int n)) = n
   to _ = error "Integer expected"

instance fromInt :: From Int where
   from = V.Int >>> val

true_ :: Val
true_ = val $ V.Constr cTrue Nil

false_ :: Val
false_ = val $ V.Constr cFalse Nil

instance fromBoolean :: From Boolean where
   from b = if b then true_ else false_

instance fromString :: From String where
   from = V.Str >>> val

applyBinary :: BinaryOp -> Val -> Val -> Val
applyBinary (BinaryOp _ (IntIntInt f)) v v' = from $ f (to v) (to v')
applyBinary (BinaryOp _ (IntIntBool f)) v v' = from $ f (to v) (to v')

applyBinary_fwd :: BinaryOp -> Selected -> Val -> Val -> Val
applyBinary_fwd op α v@(Val α1 _) v'@(Val α2 _) =
   Val (α ∧ α1 ∧ α2) u where Val _ u = applyBinary op v v'

applyUnary :: UnaryOp -> Val -> Val
applyUnary (UnaryOp _ (IntStr f)) = to >>> f >>> from
applyUnary (PartialApp φ v) = applyBinary φ v

applyUnary_fwd :: UnaryOp -> Selected -> Val -> Val
applyUnary_fwd op α v@(Val α' _) =
   Val (α ∧ α') u where Val _ u = applyUnary op v

intStr :: String -> (Int -> String) -> Val
intStr name = IntStr >>> UnaryOp name >>> V.Unary >>> val

intIntBool :: String -> (Int -> Int -> Boolean) -> Val
intIntBool name = IntIntBool >>> BinaryOp name >>> V.Binary >>> val

intIntInt :: String -> (Int -> Int -> Int) -> Val
intIntInt name = IntIntInt >>> BinaryOp name >>> V.Binary >>> val

primitives :: Env
primitives = foldl (:+:) Empty [
   "+"         ↦ intIntInt "prim-plus"    (+),
   "-"         ↦ intIntInt "prim-minus"   (-),
   "*"         ↦ intIntInt "prim-times"   (*),
   "div"       ↦ intIntInt "prim-div"     div,
   "=="        ↦ intIntBool "prim-eq"     (==),
   "/="        ↦ intIntBool "prim-eq"     (/=),
   "<"         ↦ intIntBool "prim-lt"     (<),
   ">"         ↦ intIntBool "prim-gt"     (>),
   "<="        ↦ intIntBool "prim-leq"    (<=),
   ">="        ↦ intIntBool "prim-geq"    (>=),
   "intToStr"  ↦ intStr "prim-intToStr"   show
]

append :: Expr -> Expr -> Expr
append e1 e2 = fromList $ (toList e1) <> (toList e2)

concat :: Expr -> Expr
concat e1 = fromList $ L.concat $ P.map toList (toList e1)

map :: Elim -> Expr -> Expr
map σ e = fromList $ P.map (applyσ σ) (toList e)
   where applyσ :: Elim -> Expr -> Expr
         applyσ σ' e' = expr $ E.MatchAs e' σ'

concatMap :: Elim -> Expr -> Expr
concatMap = map
