module Util.Parse where

import Prelude hiding (absurd)
import Control.Apply (lift2)
import Control.MonadPlus (empty)
import Data.Maybe (Maybe(..))
import Data.List (List, (:), many)
import Data.List (some) as L
import Data.List.NonEmpty (NonEmptyList, fromList)
import Text.Parsing.Parser (Parser)
import Text.Parsing.Parser.Combinators (try)
import Text.Parsing.Parser.Combinators (sepBy1) as P
import Util (absurd, fromBool, fromJust)

type SParser = Parser String

-- helpers (could generalise further)
pureMaybe :: forall a . Maybe a -> SParser a
pureMaybe Nothing    = empty
pureMaybe (Just x)   = pure x

pureIf :: forall a . Boolean -> a -> SParser a
pureIf b = fromBool b >>> pureMaybe

sepBy1 :: forall a sep . SParser a -> SParser sep -> SParser (NonEmptyList a)
sepBy1 p sep = fromJust absurd <$> (fromList <$> P.sepBy1 p sep)

-- sepBy1 with backtracking for successive phrases
sepBy1_try :: forall a sep . SParser a -> SParser sep -> SParser (List a)
sepBy1_try p sep = p `lift2 (:)` many (try $ sep *> p)

some :: forall a . SParser a → SParser (NonEmptyList a)
some p = fromJust absurd <$> (fromList <$> L.some p)
