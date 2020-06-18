module Parse where

import Prelude hiding (absurd, add, between, join)
import Control.Alt ((<|>))
import Control.Apply (lift2)
import Control.Lazy (fix)
import Control.MonadPlus (empty)
import Data.Array (fromFoldable)
import Data.Char.Unicode (isUpper)
import Data.Either (choose)
import Data.Function (on)
import Data.Identity (Identity)
import Data.List (List, (:), many, groupBy, some, sortBy)
import Data.List.NonEmpty (NonEmptyList, fromList, head)
import Data.Map (singleton, values)
import Data.Maybe (Maybe(..))
import Data.Ordering (invert)
import Data.String.CodeUnits (charAt)
import Data.Tuple (fst, snd)
import Debug.Trace (trace)
import Text.Parsing.Parser (Parser, fail)
import Text.Parsing.Parser.Combinators (sepBy1, try)
import Text.Parsing.Parser.Expr (Assoc(..), Operator(..), OperatorTable, buildExprParser)
import Text.Parsing.Parser.Language (emptyDef)
import Text.Parsing.Parser.String (char, eof, oneOf)
import Text.Parsing.Parser.Token (
  GenLanguageDef(..), LanguageDef, TokenParser,
  alphaNum, letter, makeTokenParser, unGenLanguageDef
)
import Bindings (Var)
import DataType (Ctr(..), cPair)
import Expr (Cont(..), Def(..), Elim(..), Expr(..), Module(..), RawExpr(..), RecDef(..), RecDefs, expr)
import PElim (Pattern(..), PCont(..), joinAll, joinAll2, mapCont, mapCont2)
import Primitive (OpName(..), opNames, opPrec)
import Util (type (×), (×), absurd, error, fromBool, fromJust)

type SParser = Parser String

-- helpers
pureMaybe :: forall a . String -> Maybe a -> SParser a
pureMaybe msg Nothing = fail msg
pureMaybe _ (Just x) = pure x

pureIf :: forall a . String -> Boolean -> a -> SParser a
pureIf msg b = fromBool b >>> pureMaybe msg

-- constants (should also be used by prettyprinter)
strArrow       = "->" :: String
strAs          = "as" :: String
strBackslash   = "\\" :: String
strEquals      = "=" :: String
strFun         = "fun" :: String
strLet         = "let" :: String
strMatch       = "match" :: String

languageDef :: LanguageDef
languageDef = LanguageDef (unGenLanguageDef emptyDef) {
   commentStart = "{-",
   commentEnd = "-}",
   commentLine = "--",
   nestedComments = true,
   identStart = letter,
   identLetter = alphaNum <|> oneOf ['_', '\''],
   opStart = opChar,
   opLetter = opChar,
   reservedOpNames = [],
   reservedNames = [strAs, strFun, strLet, strMatch],
   caseSensitive = true
} where
   opChar :: SParser Char
   opChar = oneOf [
      ':', '!', '#', '$', '%', '&', '*', '+', '.', '/', '<', '=', '>', '?', '@', '\\', '^', '|', '-', '~'
   ]

token :: TokenParser
token = makeTokenParser languageDef

keyword ∷ String → SParser Unit
keyword = token.reserved

variable :: SParser Expr
variable = ident <#> Var >>> expr

-- TODO: anonymous variables
patternVariable :: SParser Elim
patternVariable = ElimVar <$> ident <@> None

patternVariable2 :: SParser Pattern
patternVariable2 = PattVar <$> ident <@> PNone

-- Distinguish constructors from identifiers syntactically, a la Haskell. In particular this is useful
-- for distinguishing pattern variables from nullary constructors when parsing patterns.
isCtr ∷ String → Boolean
isCtr str = case charAt 0 str of
   Nothing -> error absurd
   Just ch -> isUpper ch

ident ∷ SParser Var
ident = do
   x <- token.identifier
   pureIf ("Unexpected constructor") (not (isCtr x)) x

ctr :: SParser Ctr
ctr = do
   x <- token.identifier
   pureIf ("Unexpected identifier") (isCtr x) $ Ctr x

-- Parse a constructor name as a nullary constructor pattern.
ctr_pattern :: SParser Elim
ctr_pattern = ElimConstr <$> (singleton <$> ctr <@> None)

ctr_pattern2 :: SParser Pattern
ctr_pattern2 = PattConstr <$> ctr <@> PNone

theCtr :: Ctr -> SParser Ctr
theCtr c = do
   c' <- ctr
   pureIf ("Expected " <> show c) (c' == c) c

signOpt :: ∀ a . (Ring a) => SParser (a -> a)
signOpt =
   (char '-' $> negate) <|>
   (char '+' $> identity) <|>
   pure identity

int :: SParser Expr
int = do
   sign <- signOpt
   token.natural <#> sign >>> Int >>> expr

string :: SParser Expr
string = token.stringLiteral <#> Str >>> expr

constrExpr :: SParser Expr
constrExpr =
   expr <$> (Constr <$> ctr <@> empty)

constrPattern :: SParser Elim -> SParser Elim
constrPattern pattern' = ctr_pattern >>= rest 0
   where
      rest ∷ Int -> Elim -> SParser Elim
      rest n σ = do
         σ' <- simplePattern pattern' <|> ctr_pattern
         rest (n + 1) $ fromJust absurd $ mapCont (Arg n σ') σ
         <|> pure σ

pair :: SParser Expr -> SParser Expr
pair expr' =
   token.parens $ do
      e <- expr' <* token.comma
      e' <- expr'
      pure $ expr $ Constr cPair (e : e' : empty)

patternPair :: SParser Elim -> SParser Elim
patternPair pattern' =
   token.parens $ do
      σ <- pattern' <* token.comma
      τ <- pattern'
      pure $ ElimConstr $ singleton cPair $ Arg 0 $ fromJust absurd $ mapCont (Arg 1 τ) σ

patternPair2 :: SParser Pattern -> SParser Pattern
patternPair2 pattern' =
   token.parens $ do
      π <- pattern' <* token.comma
      π' <- pattern'
      pure $ PattConstr cPair $ PArg 0 $ mapCont2 (PArg 1 π') π

-- TODO: float
simpleExpr :: SParser Expr -> SParser Expr
simpleExpr expr' =
   try constrExpr <|>
   try variable <|>
   try int <|> -- int may start with +/-
   string <|>
   let_ expr' <|>
   letRec expr' <|>
   matchAs expr' <|>
   try (token.parens expr') <|>
   try parensOp <|>
   pair expr' <|>
   lambda expr'

-- Singleton eliminator with no continuation.
simplePattern :: SParser Elim -> SParser Elim
simplePattern pattern' =
   try patternVariable <|>
   try (token.parens pattern') <|>
   patternPair pattern'

simplePattern2 :: SParser Pattern -> SParser Pattern
simplePattern2 pattern' =
   try ctr_pattern2 <|>
   try patternVariable2 <|>
   try (token.parens pattern') <|>
   patternPair2 pattern'

lambda :: SParser Expr -> SParser Expr
lambda expr' = expr <$> (Lambda <$> (keyword strFun *> elim2 true expr'))

arrow :: SParser Unit
arrow = token.reservedOp strArrow

equals :: SParser Unit
equals = token.reservedOp strEquals

patternDelim :: SParser Unit
patternDelim = arrow <|> equals

-- "nest" controls whether nested (curried) functions are permitted in this context
elim :: SParser Expr -> Boolean -> SParser Elim
elim expr' nest = elimOne patternDelim <|> elimMany
   where
   elimMany :: SParser Elim
   elimMany =
      token.braces $ do
         σs <- sepBy1 (elimOne arrow) token.semi
         pure $ fromJust "Incompatible branches" $ joinAll σs

   elimOne :: SParser Unit -> SParser Elim
   elimOne delim = do
      σ <- pattern
      e <- delim *> expr' <|> nestedFun nest expr'
      pure $ fromJust absurd $ mapCont (Body e) σ

elim2 :: Boolean -> SParser Expr -> SParser Elim
elim2 curried expr' = fromJust "Incompatible branches" <$> (joinAll2 <$> patterns curried expr')

patterns :: Boolean -> SParser Expr -> SParser (NonEmptyList Pattern)
patterns curried expr' = pure <$> patternOne curried expr' patternDelim <|> patternMany
   where
   patternMany :: SParser (NonEmptyList Pattern)
   patternMany = do
      πs <- token.braces $ sepBy1 (patternOne curried expr' arrow) token.semi
      pure $ fromJust absurd $ fromList πs

patternOne :: Boolean -> SParser Expr -> SParser Unit -> SParser Pattern
patternOne curried expr' delim = pattern' >>= rest
   where
   rest :: Pattern -> SParser Pattern
   rest π = mapCont2 <$> body' <@> π
      where
      body' = if curried then body <|> PLambda <$> (pattern' >>= rest) else body

   pattern' = if curried then simplePattern2 pattern2 else pattern2
   body = PBody <$> (delim *> expr')

nestedFun :: Boolean -> SParser Expr -> SParser Expr
nestedFun true expr' = expr <$> (Lambda <$> elim expr' true)
nestedFun false _ = empty

def :: SParser Expr -> SParser Def
def expr' =
   Def <$> try (keyword strLet *> pattern <* patternDelim) <*> expr' <* token.semi

let_ ∷ SParser Expr -> SParser Expr
let_ expr' = expr <$> (Let <$> def expr' <*> expr')

clauses :: SParser Expr -> SParser (List (Var × Pattern))
clauses expr' = do
   some $ try $ clause <* token.semi
   where
   clause :: SParser (Var × Pattern)
   clause = ident `lift2 (×)` (patternOne true expr' equals)

recDef :: SParser Expr -> SParser RecDef
recDef expr' = RecDef <$> ident <*> (elim expr' true <* token.semi)

recDefs_old :: SParser Expr -> SParser RecDefs
recDefs_old expr' = keyword strLet *> many (try $ recDef expr')

recDefs :: SParser Expr -> SParser RecDefs
recDefs expr' = do
   fπs <- keyword strLet *> clauses expr'
   let fπss = groupBy (eq `on` fst) fπs
   pure $ map toRecDef fπss
      where
      toRecDef :: NonEmptyList (String × Pattern) -> RecDef
      toRecDef fπs =
         let f = fst $ head fπs in
         RecDef f $ fromJust ("Incompatible branches for '" <> f <> "'") $ joinAll2 $ map snd fπs

letRec :: SParser Expr -> SParser Expr
letRec expr' = expr <$>
   (LetRec <$> recDefs expr' <*> expr')

matchAs :: SParser Expr -> SParser Expr
matchAs expr' = expr <$>
   (MatchAs <$> (keyword strMatch *> expr' <* keyword strAs) <*> elim2 false expr')

-- any binary operator, in parentheses
parensOp :: SParser Expr
parensOp = token.parens $ token.operator <#> Op >>> expr

-- the specific binary operator
theBinaryOp :: Var -> SParser (Expr -> Expr -> Expr)
theBinaryOp op = try $ do
   op' <- token.operator
   pureMaybe ("Expected " <> op) $
      fromBool (op == op') (\e1 -> expr <<< BinaryApp e1 op)

backtick :: SParser Unit
backtick = token.reservedOp "`"

appChain :: SParser Expr -> SParser Expr
appChain expr' = simpleExpr expr' >>= rest
   where
   rest :: Expr -> SParser Expr
   rest e@(Expr _ (Constr c es)) = ctrArgs <|> pure e
      where
      ctrArgs :: SParser Expr
      ctrArgs = simpleExpr expr' >>= \e' -> rest (expr $ Constr c (es <> (e' : empty)))
   rest e = (expr <$> (App e <$> simpleExpr expr') >>= rest) <|> pure e

-- Singleton eliminator with no continuation. Analogous in some way to app_chain, but there is nothing
-- higher-order here: no explicit application nodes, non-saturated constructor applications, or patterns
-- other than constructors in the function position.
appChain_pattern :: SParser Elim -> SParser Elim
appChain_pattern pattern' = simplePattern pattern' <|> constrPattern pattern'

appChain_pattern2 :: SParser Pattern -> SParser Pattern
appChain_pattern2 pattern' = simplePattern2 pattern' >>= rest 0
   where
      rest ∷ Int -> Pattern -> SParser Pattern
      rest n π@(PattConstr _ _) = ctrArgs <|> pure π
         where
         ctrArgs :: SParser Pattern
         ctrArgs = simplePattern2 pattern' >>= \π' -> rest (n + 1) $ mapCont2 (PArg n π') π
      rest _ π@(PattVar _ _) = pure π

-- TODO: allow infix constructors, via buildExprParser
pattern :: SParser Elim
pattern = fix appChain_pattern

pattern2 :: SParser Pattern
pattern2 = fix appChain_pattern2

-- each element of the top-level list corresponds to a precedence level
operators :: OperatorTable Identity String Expr
operators =
   fromFoldable $ map fromFoldable $
   map (map (\(OpName op _) -> Infix (theBinaryOp op) AssocLeft)) $
   groupBy (eq `on` opPrec) $ sortBy (\x -> comparing opPrec x >>> invert) $ values opNames

-- An expression is an operator tree. An operator tree is a tree whose branches are
-- binary primitives and whose leaves are application chains. An application chain
-- is a left-associative tree of one or more simple terms. A simple term is any
-- expression other than an operator tree or an application chain.
expr_ :: SParser Expr
expr_ = fix $ appChain >>> buildExprParser operators

topLevel :: forall a . SParser a -> SParser a
topLevel p = token.whiteSpace *> p <* eof

program ∷ SParser Expr
program = topLevel expr_

module_ :: SParser Module
module_ = topLevel $ many (choose (def expr_) (recDefs expr_)) <#> Module
