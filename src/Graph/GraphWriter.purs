module Graph.GraphWriter
   ( AdjMapEntries
   , WithGraphT
   , WithGraph2
   , WithGraph2T
   , class MonadGraphWriter
   , class MonadGraphWriter2
   , alloc
   , extend
   , fresh
   , new
   , runWithGraph2
   , runWithGraph2T
   , runWithGraphT
   ) where

import Prelude 
import Control.Monad.Except (runExceptT)
import Control.Monad.State.Trans (StateT, runStateT, modify, modify_)
import Data.Identity (Identity)
import Data.List (List(..), (:))
import Data.Newtype (unwrap)
import Data.Tuple (swap)
import Data.Profunctor.Strong (first, second)
import Data.Traversable (class Traversable, traverse)
import Graph (Vertex(..), class Graph, fromFoldable)
import Util (MayFailT, MayFail, type (×), (×))

class Monad m <= MonadGraphWriter2 s m | m -> s where
   -- Extend graph with existing vertex pointing to set of existing vertices.
   extend :: Vertex -> s Vertex -> m Unit

class Monad m <= MonadGraphWriter s m | m -> s where
   fresh :: m Vertex
   -- Extend with a freshly allocated vertex.
   new :: s Vertex -> m Vertex

-- List of adjacency map entries to serve as a fromFoldable input.
type AdjMapEntries s = List (Vertex × s Vertex)
type WithGraphT s m a = MayFailT (StateT (Int × AdjMapEntries s) m) a
type WithGraph2T s m a = StateT (AdjMapEntries s) m a
type WithGraph2 s a = WithGraph2T s Identity a

instance Monad m => MonadGraphWriter s (MayFailT (StateT (Int × AdjMapEntries s) m)) where
   fresh = do
      n × _ <- modify $ first $ (+) 1
      pure (Vertex $ show n)

   new αs = do
      α <- fresh
      modify_ $ second $ (:) (α × αs)
      pure α

instance Monad m => MonadGraphWriter2 s (StateT (AdjMapEntries s) m) where
   extend α αs =
      void $ modify_ $ (:) (α × αs)

alloc :: forall s m t a. Monad m => Traversable t => t a -> WithGraphT s m (t Vertex)
alloc = traverse (const fresh)

runWithGraph2T :: forall g s m a. Monad m => Graph g s => WithGraph2T s m a -> m (g × a)
runWithGraph2T c = runStateT c Nil <#> swap <#> first fromFoldable

runWithGraph2 :: forall g s a. Graph g s => WithGraph2 s a -> g × a
runWithGraph2 c = unwrap $ runWithGraph2T c

runWithGraphT :: forall g s m a. Monad m => Graph g s => (g × Int) -> WithGraphT s m a -> m (MayFail ((g × Int) × a))
runWithGraphT (g × n) e = do
   maybe_r × n' × g_adds <- (flip runStateT (n × Nil) <<< runExceptT) e
   pure $ ((×) ((g <> fromFoldable g_adds) × n')) <$> maybe_r
