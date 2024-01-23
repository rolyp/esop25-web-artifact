-- Better name and more consistent interface to Foreign.Object, plus some additional functions.
-- Maybe upgrade Dict into a full replacement of Foreign.Object; in particular Ord instance
-- seems broken (rather than isSubmap, compares on toAscArray).
module Dict
   ( module Foreign.Object
   , Dict
   , (\\)
   , (∩)
   , (∪)
   , apply
   , apply2
   , asSingletonMap
   , difference
   , insertWith
   , intersection
   , intersectionWith
   , lift2
   , toUnfoldable
   , unzip
   , values
   ) where

import Prelude hiding (apply)

import Data.Foldable (foldl)
import Data.List (List, head)
import Data.List (fromFoldable) as L
import Data.Maybe (Maybe(..), maybe)
import Data.Tuple (fst, snd)
import Data.Unfoldable (class Unfoldable)
import Foreign.Object (Object, keys, toAscUnfoldable, values) as O
import Foreign.Object (alter, delete, empty, filter, filterKeys, fromFoldable, insert, isEmpty, lookup, mapWithKey, member, singleton, size, toArrayWithKey, union, unionWith)
import Util (type (×), assert, definitely, (×))

type Dict a = O.Object a

-- `Apply` instance would be an orphan
apply :: forall a b. Dict (a -> b) -> Dict a -> Dict b
apply = intersectionWith ($) -- why not require dicts to have same shape?

apply2 :: forall f a b. Apply f => Dict (f (a -> b)) -> Dict (f a) -> Dict (f b)
apply2 d = apply ((<*>) <$> d)

lift2 :: forall f a b c. Apply f => (a -> b -> c) -> Dict (f a) -> Dict (f b) -> Dict (f c)
lift2 f d1 = apply2 ((f <$> _) <$> d1)

-- Unfortunately Foreign.Object doesn't define this; could implement using Foreign.Object.ST instead.
foreign import intersectionWith :: forall a b c. (a -> b -> c) -> Dict a -> Dict b -> Dict c

intersection :: forall a b. Dict a -> Dict b -> Dict a
intersection = intersectionWith const

difference :: forall a b. Dict a -> Dict b -> Dict a
difference m1 m2 = foldl (flip delete) m1 (O.keys m2)

infixr 7 intersection as ∩
infixr 6 union as ∪
infix 5 difference as \\

values :: forall a. Dict a -> List a
values = O.values >>> L.fromFoldable

asSingletonMap :: forall a. Dict a -> String × a
asSingletonMap m = assert (size m == 1) (definitely "singleton map" (head (toUnfoldable m)))

toUnfoldable :: forall a f. Unfoldable f => Dict a -> f (String × a)
toUnfoldable = O.toAscUnfoldable

unzip :: forall a b. Dict (a × b) -> Dict a × Dict b
unzip kvs = (kvs <#> fst) × (kvs <#> snd)

insertWith :: forall a. (a -> a -> a) -> String -> a -> Dict a -> Dict a
insertWith f k v = alter (Just <<< maybe v (flip f v)) k
