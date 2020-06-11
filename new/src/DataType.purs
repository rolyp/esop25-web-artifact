module DataType where

import Prelude
import Data.Foldable (class Foldable)
import Data.List (List)
import Data.List (fromFoldable) as L
import Data.Map (Map, fromFoldable)
import Data.Newtype (class Newtype)
import Data.Tuple (Tuple(..))

newtype Ctr = Ctr String
derive instance newtypeCtr :: Newtype Ctr _
derive instance eqCtr :: Eq Ctr
derive instance ordCtr :: Ord Ctr

data DataType = DataType String (Map Ctr CtrSig)
data CtrSig = CtrSig Ctr (List String)

ctr :: forall f . Foldable f => String -> f String -> Tuple Ctr CtrSig
ctr c = L.fromFoldable >>> CtrSig (Ctr c) >>> Tuple (Ctr c)

dataType :: forall f . Foldable f => String -> f (Tuple Ctr CtrSig) -> DataType
dataType name = fromFoldable >>> DataType name

dataTypes :: List DataType
dataTypes = L.fromFoldable [
   dataType "Bool" [
      ctr "True" [],
      ctr "False" []
   ],
   dataType "List" [
      ctr "Nil" [],
      ctr "Cons" ["head", "tail"]
   ]
]
