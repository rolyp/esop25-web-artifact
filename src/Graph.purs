module Graph where

import Prelude

import Control.Monad.State (State, StateT, get, put)
import Data.Foldable (foldl)
import Data.List (List(..), (:))
import Data.List (fromFoldable) as L
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype, unwrap)
import Data.Set (Set)
import Data.Set (delete, difference, empty, filter, fromFoldable, isEmpty, map, member, singleton, subset, union, unions) as S
import Data.Tuple (fst)
import Foreign.Object (Object, delete, empty, filterKeys, fromFoldable, keys, lookup, singleton, size, unionWith) as SM
import Util (Endo, (×), type (×))

type SMap = SM.Object

class Graph g where
   union :: Vertex -> Set Vertex -> Endo g
   outN :: g -> Vertex -> Maybe (Set Vertex)
   inN :: g -> Vertex -> Maybe (Set Vertex)
   singleton :: Vertex -> Set Vertex -> g
   remove :: Vertex -> Endo g
   opp :: Endo g
   allocate :: g -> Vertex

newtype Vertex = Vertex String

type HeapT m a = StateT Int m a
type Heap a = State Int a

fresh :: forall m. Monad m => HeapT m Vertex
fresh = do
   s <- get
   put (s + 1)
   pure (Vertex (show s))

newtype GraphImpl = GraphImpl ((SMap (Set Vertex)) × (SMap (Set Vertex)))

instance Graph GraphImpl where
   allocate (GraphImpl (out × _)) = Vertex α
      where
      α = show $ 1 + (SM.size out)
   remove (Vertex α) (GraphImpl (out × in_)) =
      let
         newOutN = map (S.delete (Vertex α)) (SM.delete α out)
         newInN = map (S.delete (Vertex α)) (SM.delete α in_)
      in
         GraphImpl (newOutN × newInN)
   union α αs (GraphImpl (out × in_)) = (GraphImpl (newOut × newIn))
      where
      newOut = SM.unionWith S.union out (starInOut α αs)
      newIn = SM.unionWith S.union in_ (starInIn α αs)

   outN (GraphImpl (out × _)) (Vertex α) = SM.lookup α out
   inN (GraphImpl (_ × in_)) (Vertex α) = SM.lookup α in_

   singleton α αs = GraphImpl (starInOut α αs × starInIn α αs)
   opp (GraphImpl (out × in_)) = GraphImpl (in_ × out)

emptyG :: GraphImpl
emptyG = GraphImpl (SM.empty × SM.empty)

subgraph :: GraphImpl -> Set Vertex -> GraphImpl
subgraph (GraphImpl (out × in_)) αs =
   let
      keys = S.fromFoldable $ SM.keys out
      αNames = S.map unwrap αs
   in
      if S.subset αNames keys then
         let
            αs' = S.map Vertex (S.difference keys αNames)
            filteredOut = SM.filterKeys (\k -> S.member k αNames) out
            filteredIn = SM.filterKeys (\k -> S.member k αNames) in_
            newOut = map (\set -> S.difference set αs') filteredOut
            newIn = map (\set -> S.difference set αs') filteredIn
         in
            GraphImpl (newOut × newIn)
      else
         emptyG

outE' :: forall g. Graph g => g -> Vertex -> Set (Vertex × Vertex)
outE' graph α = case outN graph α of
   Just set -> S.map (\node -> α × node) set
   Nothing -> S.empty

outE :: Set Vertex -> GraphImpl -> Set (Vertex × Vertex)
outE αs g =
   let
      allOut = S.unions (S.map (\α -> outE' g α) αs)
   in
      S.filter (\(e1 × e2) -> (S.member e1 αs || S.member e2 αs)) allOut

inE' :: forall g. Graph g => g -> Vertex -> Set (Vertex × Vertex)
inE' graph α = case inN graph α of
   Just set -> S.map (\node -> α × node) set
   Nothing -> S.empty

inE :: Set Vertex -> GraphImpl -> Set (Vertex × Vertex)
inE αs g =
   let
      allIn = S.unions (S.map (\α -> inE' g α) αs)
   in
      S.filter (\(e1 × e2) -> S.member e1 αs || S.member e2 αs) allIn

-- Initial attempts at making stargraphs, using foldl to construct intermediate objects
outStarOld :: Vertex -> Set Vertex -> SMap (Set Vertex)
outStarOld (Vertex α) αs = foldl (SM.unionWith S.union) (SM.singleton α αs) (S.map (\(Vertex α') -> SM.singleton α' S.empty) αs)

inStarOld :: Vertex -> Set Vertex -> SMap (Set Vertex)
inStarOld (Vertex α) αs = foldl (SM.unionWith S.union) (SM.singleton α S.empty) (S.map (\(Vertex α') -> SM.singleton α' (S.singleton (Vertex α))) αs)

-- prototype attempts at more efficiently implementing the above operations
starInOut :: Vertex -> Set Vertex -> SMap (Set Vertex)
starInOut α αs = buildStar α αs star'

buildStar :: Vertex -> Set Vertex -> (Vertex -> Set Vertex -> SMap (Set Vertex)) -> SMap (Set Vertex)
buildStar v@(Vertex α) αs f = SM.unionWith S.union (SM.singleton α αs) (f v αs)

buildStar' :: Vertex -> Set Vertex -> (Vertex -> Set Vertex -> SMap (Set Vertex)) -> SMap (Set Vertex)
buildStar' v@(Vertex α) αs f = SM.unionWith S.union (SM.singleton α S.empty) (f v αs)

star' :: Vertex -> Set Vertex -> SMap (Set Vertex)
star' _α αs = SM.fromFoldable $ S.map (\(Vertex α') -> α' × S.empty) αs

star'' :: Vertex -> Set Vertex -> SMap (Set Vertex)
star'' α αs = SM.fromFoldable $ S.map (\(Vertex α') -> α' × (S.singleton α)) αs

starInIn :: Vertex -> Set Vertex -> SMap (Set Vertex)
starInIn α αs = buildStar' α αs star''

inStar :: Vertex -> Set Vertex -> GraphImpl
inStar α αs = opp (outStar α αs)

outStar :: Vertex -> Set Vertex -> GraphImpl
outStar α αs = GraphImpl ((starInOut α αs) × (starInIn α αs))

elem :: GraphImpl -> Vertex -> Boolean
elem (GraphImpl (out × _)) (Vertex α) =
   case SM.lookup α out of
      Just _ -> true
      Nothing -> false

bwdSlice :: Set Vertex -> GraphImpl -> GraphImpl
bwdSlice αs parent = bwdSlice' parent startG edges
   where
   startG = subgraph parent αs
   edges = L.fromFoldable $ outE αs parent

bwdSlice' :: GraphImpl -> GraphImpl -> List (Vertex × Vertex) -> GraphImpl
bwdSlice' parent g ((s × t) : es) =
   if elem g t then
      let
         newG = union t (outNSet parent t) g
      in
         bwdSlice' parent newG es
   else
      let
         newG = union s (S.singleton t) g
         newEs = append es (L.fromFoldable (outE' parent t))
      in
         bwdSlice' parent newG newEs
   where
   outNSet :: GraphImpl -> Vertex -> Set Vertex
   outNSet g' v = case outN g' v of
      Just neighbs -> neighbs
      Nothing -> S.empty

   append :: forall a. List a -> List a -> List a
   append Nil xs = xs
   append (y : ys) xs = append ys (y : xs)

bwdSlice' _ g Nil = g

fwdSlice :: Set Vertex -> GraphImpl -> GraphImpl
fwdSlice αs parent = fst $ fwdEdges startG emptyG edges
   where
   startG = subgraph parent αs
   edges = inE αs parent

fwdEdges :: GraphImpl -> GraphImpl -> Set (Vertex × Vertex) -> GraphImpl × GraphImpl
fwdEdges currSlice pending edges =
   if S.isEmpty edges then currSlice × pending
   else
      emptyG × emptyG

derive instance Eq Vertex
derive instance Ord Vertex
derive instance Newtype Vertex _

instance Show Vertex where
   show (Vertex α) = "Vertex " <> α

instance Show GraphImpl where
   show (GraphImpl (out × in_)) = "GraphImpl (" <> show out <> " × " <> show in_ <> ")"
