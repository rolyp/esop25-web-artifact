module PElim where

import Prelude hiding (absurd, join)
import Data.Either (Either(..))
import Data.List (List(..), (:))
import Data.List.NonEmpty (NonEmptyList(..))
import Data.Map (Map, insert, lookup, singleton, update)
import Data.Map.Internal (keys)
import Data.Maybe (Maybe(..))
import Data.NonEmpty ((:|))
import Data.Traversable (foldl)
import Bindings (Var)
import DataType (DataType, Ctr, dataTypeFor, typeName)
import Expr (Cont(..), Elim(..), Expr(..), RawExpr(..), expr)
import Util (MayFail, (≟=), absurd, error, om)

data PCont =
   PNone |              -- intermediate state during construction, but also for structured let
   PBody Expr |
   PLambda Pattern |    -- unnecessary if surface language supports piecewise definitions
   PArg Pattern |
   PArgsEnd PCont

toCont :: PCont -> Cont
toCont PNone         = None
toCont (PBody e)     = Body e
toCont (PLambda π)   = Body $ expr $ Lambda $ toElim π
toCont (PArg π)      = Arg $ toElim π
toCont (PArgsEnd κ)  = ArgsEnd $ toCont κ

data Pattern =
   PattVar Var PCont |
   PattConstr Ctr PCont

toElim :: Pattern -> Elim
toElim (PattVar x κ)    = ElimVar x $ toCont κ
toElim (PattConstr c κ) = ElimConstr $ singleton c $ toCont κ

class MapCont a where
   -- replace a None continuation by a non-None one
   setCont :: PCont -> a -> a

instance setContPCont :: MapCont PCont where
   setCont κ PNone         = κ
   setCont κ (PBody _)     = error absurd
   setCont κ (PLambda π)   = PLambda $ setCont κ π
   setCont κ (PArg π)      = PArg $ setCont κ π
   setCont κ (PArgsEnd κ') = PArgsEnd $ setCont κ κ'

instance setContPattern :: MapCont Pattern where
   setCont κ (PattVar x κ')     = PattVar x $ setCont κ κ'
   setCont κ (PattConstr c κ')  = PattConstr c $ setCont κ κ'

class Joinable a b | a -> b where
   maybeJoin :: b -> a -> MayFail b

dataType :: Map Ctr Cont -> MayFail DataType
dataType κs = case keys κs of
   Nil   -> error absurd
   c : _ -> dataTypeFor c

instance joinablePatternElim :: Joinable Pattern Elim where
   maybeJoin (ElimVar x κ) (PattVar y κ')      = ElimVar <$> x ≟= y <*> maybeJoin κ κ'
   maybeJoin (ElimConstr κs) (PattConstr c κ)  = ElimConstr <$> mayFailUpdate
      where
      mayFailUpdate :: MayFail (Map Ctr Cont)
      mayFailUpdate =
         case lookup c κs of
            Nothing -> do
               checkDataType
               insert <$> pure c <@> toCont κ <@> κs
               where
               checkDataType :: MayFail Unit
               checkDataType = do
                  d <- dataType κs
                  d' <- dataTypeFor c
                  void $ typeName d ≟= typeName d'
            Just κ' -> update <$> (const <$> pure <$> maybeJoin κ' κ) <@> c <@> κs
   maybeJoin _ _                               = Left "Can't join variable and constructor patterns"

instance joinablePContCont :: Joinable PCont Cont where
   maybeJoin None PNone                               = pure None
   maybeJoin (Arg σ) (PArg π)                         = Arg <$> maybeJoin σ π
   maybeJoin (ArgsEnd κ) (PArgsEnd κ')                = ArgsEnd <$> maybeJoin κ κ'
   maybeJoin (Body (Expr _ (Lambda σ))) (PLambda π)   = Body <$> (expr <$> (Lambda <$> maybeJoin σ π))
   maybeJoin _ _                                      = Left "Incompatible continuations"

joinAll :: NonEmptyList Pattern -> MayFail Elim
joinAll (NonEmptyList (π :| πs)) = foldl (om $ maybeJoin) (Right $ toElim π) πs
