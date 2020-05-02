module Parse where

import Prelude hiding (between)
import Control.Alt ((<|>))
import Control.Lazy (fix)
import Text.Parsing.Parser (Parser)
import Text.Parsing.Parser.Combinators (between)
import Text.Parsing.Parser.Language (emptyDef)
import Text.Parsing.Parser.String (oneOf, string)
import Text.Parsing.Parser.Token (
  GenLanguageDef(..), LanguageDef, TokenParser,
  alphaNum, letter, makeTokenParser, unGenLanguageDef
)
import Bindings (Var)
import Expr (Expr(..))

type SParser = Parser String

-- constants (should also be used by prettyprinter)
strIn = "in" :: String
strLet = "let" :: String
strLParen = "(" :: String
strRParen = "(" :: String

parens :: forall a . SParser a -> SParser a
parens = between (string strLParen) (string strRParen)

languageDef :: LanguageDef
languageDef = LanguageDef (unGenLanguageDef emptyDef) {
   commentStart    = "{-",
   commentEnd      = "-}",
   commentLine     = "--",
   nestedComments  = true,
   identStart      = letter,
   identLetter     = alphaNum <|> oneOf ['_', '\''],
   opStart         = op',
   opLetter        = op',
   reservedOpNames = [],
   reservedNames   = [],
   caseSensitive   = true
} where
   op' :: SParser Char
   op' = oneOf [':', '!', '#', '$', '%', '&', '*', '+', '.', '/', '<', '=', '>', '?', '@', '\\', '^', '|', '-', '~']

token :: TokenParser
token = makeTokenParser languageDef

keyword ∷ String → SParser Unit
keyword = token.reserved

variable :: SParser Expr
variable = ident >>= compose pure Var

-- Need to resolve constructors vs. variables (https://github.com/explorable-viz/fluid/issues/49)
ident ∷ SParser Var
ident = token.identifier

int :: SParser Expr
int = token.integer >>= compose pure Int

pair :: SParser Expr -> SParser Expr
pair expr' = parens $ do
   e1 ← expr
   e2 ← token.comma *> expr
   pure $ Pair e1 e2

-- TODO: string, float
simpleExpr :: SParser Expr -> SParser Expr
simpleExpr expr' =
   variable <|>
   let_ expr' <|>
   int <|>
   parens expr' <|>
   pair expr'
{-
   list {% id %} |
-}

let_ ∷ SParser Expr -> SParser Expr
let_ term' = do
   keyword strLet
   x ← ident
   e1 ← token.reservedOp "=" *> term'
   e2 ← keyword strIn *> term'
   pure $ Let x e1 e2

expr :: SParser Expr
expr = fix $ \p ->
   simpleExpr p
