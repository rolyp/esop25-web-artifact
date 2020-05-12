module Expr where

import Prelude ((<>))
import Data.Eq (class Eq)
import Data.Show
import Bindings (Var)
import Primitive (BinaryOp)

data T3 a b c = T3 a b c

data Availability = Top | Bottom

data Expr = Int Int | IntSel Int
          | Var Var
          | True | TrueSel
          | False | FalseSel
          | Pair Expr Expr | PairSel Expr Expr
          | Nil | NilSel
          | Cons Expr Expr | ConsSel Expr Expr
          | Let Var Expr Expr
          | Match Expr Elim
          | Letrec String Elim Expr
          | App Expr Expr
          | Add Expr Expr
          | BinaryApp BinaryOp Expr Expr

data Elim = ElimVar { x :: Var, e :: Expr }
          | ElimPair { x :: Var, y :: Var, e:: Expr }
          | ElimList { bnil :: Expr, bcons :: { x :: Var, y :: Var, e:: Expr } }
          | ElimBool { btrue :: Expr, bfalse :: Expr }

derive instance eqT3 :: (Eq a, Eq b, Eq c) => Eq (T3 a b c)
instance showT3 :: (Show a, Show b, Show c) => Show (T3 a b c) where
  show (T3 a b c) = "T3 " <> show a <> " " <> show b <> " " <> show c

derive instance eqAvailability :: Eq Availability
instance showAvailability :: Show Availability where
  show Top    = "Top"
  show Bottom = "Bottom"

derive instance eqExpr :: Eq Expr

derive instance eqElim :: Eq Elim
