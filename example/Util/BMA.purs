module Example.Util.BMA where

import Prelude

import Data.Array (cons, head, mapMaybe, range, tail, uncons, zip, zipWith, (!!))
import Data.FastVect.FastVect (Vect)
import Data.Foldable (class Foldable, foldl)
import Data.Int (toNumber)
import Data.Maybe (Maybe(..))
import Data.Number (pow)
import Data.Int (pow) as I
import Data.Ord (abs)
import Effect (Effect)
import Effect.Class.Console (log)
import Effect.Console (logShow)
import Util (type (×), (×))

product :: forall a len. Semiring a => Vect len a -> a
product v = foldl (*) one v 

vsum :: forall a len. Semiring a => Vect len a -> a
vsum v = foldl (+) zero v

sum :: forall f a. Foldable f => Semiring a => f a -> a
sum xs = foldl (+) zero xs

vlen :: forall a len. Vect len a -> Int
vlen xs = foldl (\count _x -> (+) 1 count) 0 xs

vlenN :: forall a len. Vect len a -> Number
vlenN = toNumber <<< vlen

mean :: forall len. Number -> Vect len Number -> Number
mean 0.0 xs = product xs `pow` (1.0 / vlenN xs)
mean p xs = (1.0 / vlenN xs * vsum (map (pow p) xs)) `pow` (1.0/p)

type Matrix a = Array (Array a)

data IntInf = IInt Int | Infty
instance Show IntInf where
   show (IInt x) = "IInt" <> show x
   show (Infty) = "Infty"

instance Semiring IntInf where
   add Infty _ = Infty
   add _ Infty = Infty
   add (IInt x) (IInt y) = IInt (x + y)
   zero = IInt 0
   one = IInt 1
   mul Infty _ = Infty
   mul _ Infty = Infty
   mul (IInt x) (IInt y) = IInt (x * y)
instance Ring IntInf where -- seems potentially dangerous?
   sub Infty _ = Infty
   sub _ Infty = Infty
   sub (IInt x) (IInt y) = IInt (x - y)

instance Eq IntInf where
   eq Infty Infty = true
   eq Infty (IInt _) = false
   eq (IInt _) Infty = false
   eq (IInt x) (IInt y) = eq x y

instance Ord IntInf where
   compare Infty Infty = EQ
   compare Infty (IInt _) = GT
   compare (IInt _) Infty = LT
   compare (IInt x) (IInt y) = compare x y

ipow :: IntInf -> IntInf -> IntInf
ipow Infty _ = Infty
ipow _ Infty = Infty
ipow (IInt x) (IInt y) = IInt (x `I.pow` y)

matIndex :: forall a. Matrix a -> Int -> Int -> Maybe a
matIndex mat row col = case mat !! row of
                            Nothing  -> Nothing
                            Just arr -> arr !! col

matOfInds :: Int -> Int -> Matrix (Int × Int)
matOfInds nrows ncols = matrix
   where
   rowInds = range 1 nrows
   zipRow :: forall a. a -> Int -> Array (a × Int)
   zipRow datum num = map (\x -> datum × x) (range 1 num)
   matrix = map (\x -> zipRow x ncols) rowInds

genMat :: forall a. (Int × Int -> a) -> Int -> Int -> Matrix a
genMat f nrows ncols = f' matrix
   where
   f' = map (\row -> map (\x -> f x) row)
   matrix = matOfInds nrows ncols

mapIndMat ∷ ∀ (f71 ∷ Type -> Type) (f74 ∷ Type -> Type) (a75 ∷ Type) (b76 ∷ Type). Functor f71 ⇒ Functor f74 ⇒ (a75 → b76) → f71 (f74 a75) → f71 (f74 b76)
mapIndMat f = map (\y -> map (\x -> f x) y)

bandMatrix :: Matrix (Int × Int) -> Int -> Matrix IntInf
bandMatrix indexMat slack = mapIndMat withinBand indexMat 
   where
   withinBand :: (Int × Int) -> IntInf
   withinBand (x × y) = if (abs $ x - y) <= slack then IInt 1 else Infty

transpose :: forall a. Array (Array a) -> Array (Array a)
transpose xs =
  case uncons xs of
    Nothing ->
      xs
    Just { head: h, tail: xss } ->
      case uncons h of
        Nothing ->
          transpose xss
        Just { head: x, tail: xs' } ->
          (x `cons` mapMaybe head xss) `cons` transpose (xs' `cons` mapMaybe tail xss)

mMult :: forall a. Semiring a => Matrix a -> Matrix a -> Matrix a
mMult x y = do
   ar <- x
   bc <- (transpose y)
   pure $ [(sum $ zipWith (*) ar bc)]

mAdd :: forall a. Semiring a => Matrix a -> Matrix a -> Matrix a
mAdd x y = map (\(xR × yR) -> zipWith (+) xR yR) (zip x y)

mSub :: forall a. Ring a => Matrix a -> Matrix a -> Matrix a
mSub x y = map (\(xR × yR) -> zipWith (-) xR yR) (zip x y)

mapMatrix :: forall a b. (a -> b) -> Matrix a -> Matrix b
mapMatrix f m = map (\row -> map f row) m

matSquared :: Matrix IntInf -> Matrix IntInf
matSquared mat = mapMatrix (\x -> x `ipow` (IInt 2)) mat

main :: Effect Unit
main = do
   logShow (genMat (\(x × y) -> if (abs $ x - y) <= 3 then IInt 1 else Infty) 10 10)
   let newMat = (genMat (\(x × y) -> x + y) 3 4)
   log $ "newMat: " <> (show newMat)
   log $ "transposed: " <> (show (transpose newMat))

   let testMul = [[1, 2],[3, 4]] `mMult` [[5, 6], [7, 8]]
   logShow testMul
   let testAdd = [[1,0], [0, 1]] `mSub` [[0, 1], [1,0]]
   logShow testAdd

