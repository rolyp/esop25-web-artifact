module Util where

import Prelude hiding (absurd)

import Control.Apply (lift2)
import Control.Comonad (extract)
import Control.Monad.Error.Class (class MonadError, class MonadThrow, catchError, throwError)
import Control.Monad.Except (Except, ExceptT(..), runExceptT, except)
import Control.MonadPlus (class MonadPlus, empty)
import Data.Array ((!!), updateAt)
import Data.Either (Either(..))
import Data.Identity (Identity(..))
import Data.List (List(..), (:), intercalate)
import Data.List.NonEmpty (NonEmptyList(..))
import Data.Map (Map)
import Data.Map (lookup, unionWith) as M
import Data.Maybe (Maybe(..))
import Data.NonEmpty ((:|))
import Data.Profunctor.Strong ((&&&), (***))
import Data.Tuple (Tuple(..), fst, snd)
import Effect.Exception (throw)
import Effect.Unsafe (unsafePerformEffect)

infixr 6 type Tuple as × -- standard library has \/
infixr 6 Tuple as ×

infixr 6 type Either as + -- standard library has \/

error :: ∀ a. String -> a
error msg = unsafePerformEffect (throw msg)

assert :: ∀ a. Boolean -> a -> a
assert true = identity
assert false = \_ -> error "Assertion failure"

absurd :: String
absurd = "absurd"

unimplemented :: String
unimplemented = "unimplemented"

whenever :: forall a. Boolean -> a -> Maybe a
whenever false = const Nothing
whenever true = Just

definitely :: forall a. String -> Maybe a -> a
definitely _ (Just a) = a
definitely msg Nothing = error msg

definitely' :: forall a. Maybe a -> a
definitely' = definitely absurd

get :: forall k v. Ord k => k -> Map k v -> v
get k = definitely' <<< M.lookup k

onlyIf :: Boolean -> forall m a. MonadPlus m => a -> m a
onlyIf true = pure
onlyIf false = const empty

type MayFail a = Except String a
type MayFailT m = ExceptT String m

orElse :: forall a m. MonadThrow String m => String -> Maybe a -> m a
orElse s Nothing = throwError s
orElse _ (Just x) = pure x

ignoreMessage :: forall a. MayFail a -> Maybe a
ignoreMessage = runExceptT >>> extract >>> case _ of
   (Left _) -> Nothing
   (Right x) -> Just x

report :: String -> forall a m. Applicative m => MayFailT m a
report s = except $ Left s

fromRight :: forall a. Either String a -> a
fromRight (Right x) = x
fromRight (Left msg) = error msg

successful :: forall a. MayFail a -> a
successful (ExceptT (Identity (Right x))) = x
successful (ExceptT (Identity (Left msg))) = error msg

successfulWith :: String -> forall a. MayFail a -> a
successfulWith msg = successful <<< with msg

-- If the property fails, add an extra error message.
with :: forall a m. MonadError String m => String -> Endo (m a)
with msg m = catchError m (\msg' -> throwError $ msg' <> if msg == "" then "" else ("\n" <> msg))

check :: forall m. MonadError String m => Boolean -> String -> m Unit
check true = const $ pure unit
check false = throwError

mayEq :: forall a. Eq a => a -> a -> Maybe a
mayEq x x' = whenever (x == x') x

mustEq :: forall a. Eq a => Show a => a -> a -> a
mustEq x x' = definitely (show x <> " equal to " <> show x') (x ≟ x')

mustGeq :: forall a. Ord a => Show a => a -> a -> a
mustGeq x x' = definitely (show x <> " greater than " <> show x') (whenever (x >= x') x)

unionWithMaybe :: forall a b. Ord a => (b -> b -> Maybe b) -> Map a b -> Map a b -> Map a (Maybe b)
unionWithMaybe f m m' = M.unionWith (\x -> lift2 f x >>> join) (Just <$> m) (Just <$> m')

mayFailEq :: forall a m. MonadError String m => Show a => Eq a => a -> a -> m a
mayFailEq x x' = x ≟ x' # orElse (show x <> " ≠ " <> show x')

infixl 4 mayEq as ≟
infixl 4 mayFailEq as ≞
infixl 4 mustEq as ≜
infixl 4 mustGeq as ⪄

-- could be more efficient
intersperse :: forall a. a -> Endo (List a)
intersperse x xs = intercalate (pure x) (pure <$> xs)

om :: forall a b c m. Monad m => (a -> b -> m c) -> m a -> b -> m c
om f m x = m >>= flip f x

bind2Flipped :: forall m a b c. Monad m => (a -> b -> m c) -> m a -> m b -> m c
bind2Flipped f x y = join (lift2 f x y)

infixr 1 bind2Flipped as =<<<

type Endo a = a -> a

-- version of this in Data.Array uses unsafePartial
unsafeIndex :: forall a. Array a -> Int -> a
unsafeIndex xs i = definitely "index within bounds" (xs !! i)

unsafeUpdateAt :: forall a. Int -> a -> Endo (Array a)
unsafeUpdateAt i x = updateAt i x >>> definitely "index within bounds"

infixl 8 unsafeIndex as !

nonEmpty :: forall a. List a -> NonEmptyList a
nonEmpty Nil = error absurd
nonEmpty (x : xs) = NonEmptyList (x :| xs)

-- Also defined in Data.Profunctor.Monoidal, but perhaps not "standard library"
dup :: forall a. a -> a × a
dup x = x × x

unzip :: forall t a b. Functor t => t (a × b) -> t a × t b
unzip = map fst &&& map snd

both :: forall a b. (a -> b) -> a × a -> b × b
both f = f *** f

-- Couldn't find these in standard library
assoc1 :: forall a b c. (a × b) × c -> a × (b × c)
assoc1 ((a × b) × c) = a × (b × c)

assoc2 :: forall a b c. a × (b × c) -> (a × b) × c
assoc2 (a × (b × c)) = (a × b) × c

-- Not sure what provision there is for composition of functors with types
data WithTypeLeft (t :: Type) (f :: Type -> Type) a = WithTypeLeft t (f a)

infixr 6 type WithTypeLeft as <×|
infixr 6 WithTypeLeft as <×|

derive instance Functor f => Functor (t <×| f)
