module Graph.WithGraph where

import Prelude

import Control.Monad.Except (class MonadError)
import Control.Monad.State (StateT, runStateT, modify, modify_)
import Control.Monad.Trans.Class (lift)
import Data.Identity (Identity)
import Data.List (List(..), (:), range)
import Data.Newtype (unwrap)
import Data.Profunctor.Strong (first)
import Data.Set (Set)
import Data.Set as Set
import Data.Set.NonEmpty (NonEmptySet)
import Data.Traversable (class Traversable, traverse)
import Data.Tuple (swap)
import Debug (trace)
import Effect.Exception (Error)
import Graph (class Graph, Vertex(..), fromEdgeList, vertices)
import Lattice (Raw)
import Util (type (×), (×), (∪))

class Monad m <= MonadWithGraph m where
   -- Extend graph with existing vertex pointing to set of existing vertices.
   extend :: Vertex -> NonEmptySet Vertex -> m Unit

class Monad m <= MonadAlloc m where
   fresh :: m Vertex

-- Fix exceptions at Error, the type of JavaScript exceptions, because Aff requires Error, and
-- I can't see a way to convert MonadError Error m (for example) to MonadError Error m.
class (MonadAlloc m, MonadError Error m, MonadWithGraph m) <= MonadWithGraphAlloc m where
   -- Extend with a freshly allocated vertex.
   new :: NonEmptySet Vertex -> m Vertex

-- List of adjacency map entries to serve as a fromFoldable input.
type AdjMapEntries = List (Vertex × NonEmptySet Vertex)
type AllocT m = StateT Int m
type Alloc = AllocT Identity
type WithGraphAllocT m = AllocT (WithGraphT m)
type WithGraphT = StateT AdjMapEntries
type WithGraph = WithGraphT Identity

instance Monad m => MonadAlloc (AllocT m) where
   fresh = do
      n <- modify $ (+) 1
      pure (Vertex $ show n)

instance MonadError Error m => MonadWithGraphAlloc (WithGraphAllocT m) where
   new αs = do
      α <- fresh
      extend α αs
      pure α

instance Monad m => MonadWithGraph (WithGraphT m) where
   extend α αs =
      void $ modify_ $ (:) (α × αs)

instance Monad m => MonadWithGraph (WithGraphAllocT m) where
   extend α = lift <<< extend α

alloc :: forall m t. MonadAlloc m => Traversable t => Raw t -> m (t Vertex)
alloc = traverse (const fresh)

runAllocT :: forall m a. Monad m => Int -> AllocT m a -> m (Int × Set Vertex × a)
runAllocT n m = do
   a × n' <- runStateT m n
   -- TODO: duplicated vertex construction should be avoidable
   let fresh_αs = Set.fromFoldable $ (Vertex <<< show) <$> range (n + 1) n'
   trace (show (n + 1) <> ".." <> show n') \_ ->
      pure (n' × fresh_αs × a)

runAlloc :: forall a. Int -> Alloc a -> Int × Set Vertex × a
runAlloc n = runAllocT n >>> unwrap

runWithGraphT :: forall g m a. Monad m => Graph g => g -> WithGraphT m a -> m (g × a)
runWithGraphT g m = runStateT m Nil <#> swap <#> first (fromEdgeList (vertices g))

runWithGraph :: forall g a. Graph g => g -> WithGraph a -> g × a
runWithGraph g = runWithGraphT g >>> unwrap

runWithGraphAllocT :: forall g m a. Monad m => Graph g => g × Int -> WithGraphAllocT m a -> m ((g × Int) × a)
runWithGraphAllocT (g × n) m = do
   (n' × αs × a) × g_adds <- runStateT (runAllocT n m) Nil
   pure $ ((g <> fromEdgeList (vertices g ∪ αs) g_adds) × n') × a
