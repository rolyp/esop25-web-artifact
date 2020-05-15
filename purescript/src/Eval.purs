module Eval where

import Prelude ((<>), ($))
import Data.Maybe (Maybe(..))
import Bindings (Bindings(..), (:+:), (↦), find)
import Expl (Expl(..)) as T
import Expl (Expl, Match(..))
import Expr
import Primitive (opFun)
import Util (absurd, error)
import Val (Env, Val, toValues, val)
import Val (RawVal(..)) as V

match :: Val -> Elim -> Maybe (T3 Env Expr Match)
-- var
match v (ElimVar { x, e }) = Just $ T3 (Empty :+: x ↦ v) e (MatchVar x)
-- true
match { u: V.True } (ElimBool { true: e1, false: _ }) = Just $ T3 Empty e1 MatchTrue
-- false
match { u: V.False } (ElimBool { true: _, false: e2 }) = Just $ T3 Empty e2 MatchFalse
-- pair
match { u: V.Pair v v' } (ElimPair { x, y, e }) = Just $ T3 (Empty :+: x ↦ v :+: y ↦ v') e (MatchPair x y)
-- nil
match { u: V.Nil } (ElimList { nil: e, cons: _ }) = Just $ T3 Empty e MatchNil
-- cons
match { u : V.Cons v v' } (ElimList { nil: _, cons: { x, y, e } }) =
   Just $ T3 (Empty :+: x ↦ v :+: y ↦ v') e (MatchCons x y)
-- failure
match _ _ = Nothing

type ExplVal = { t :: Expl, v :: Val }

eval :: Env -> Expr -> ExplVal
-- var
eval ρ { r: Var x } =
   case find x ρ of
      Just v -> { t: T.Var x, v }
      _ -> error $ "variable " <> x <> " not found"
-- op
eval ρ { r: Op op } =
   case find op ρ of
      Just v -> { t: T.Op op, v }
      _ -> error $ "operator " <> op <> " not found"
-- true
eval ρ { r: True } = { t: T.True, v: val V.True }
-- false
eval ρ { r: False } = { t: T.False, v: val V.False }
-- int
eval ρ { r: Int n } = { t: T.Int n, v: val $ V.Int n }
-- pair
eval ρ { r: Pair e e' } =
   let { t, v } = eval ρ e
       { t: t', v: v' } = eval ρ e'
   in  { t: T.Pair t t', v: val $ V.Pair v v' }
-- nil
eval ρ { r: Nil } = { t: T.Nil, v: val V.Nil }
-- cons
eval ρ { r: Cons e e' } =
   let { t, v } = eval ρ e
       { t: t', v: v' } = eval ρ e'
   in { t: T.Cons t t', v: val $ V.Cons v v' }
-- letrec
eval ρ { r: Letrec f σ e } =
   let { t, v } = eval (ρ :+: f ↦ (val $ V.Closure ρ f σ)) e
   in { t: T.Letrec f (T.Fun ρ σ) t, v }
-- apply
eval ρ { r: App e e' } =
   case eval ρ e, eval ρ e' of
      { t, v: { u: V.Closure ρ' f σ } }, { t: t', v } ->
         case match v σ of
            Just (T3 ρ'' e'' ξ) ->
               let { t: u, v: v' } = eval ((ρ' <> ρ'') :+: f ↦ v) e''
               in { t: T.App t t' ξ u, v: v' }
            Nothing -> error "Value mismatch"
      { t, v: { u: V.Op op } }, { t: t', v } ->
         { t: T.AppOp t t', v: val $ V.PartialApp op v }
      { t, v: { u: V.PartialApp op v } }, { t: t', v: v' } ->
         { t: T.AppOp t t', v: toValues (opFun op) v v' }
      _, _ -> error "Expected closure or operator"
-- binary app
eval ρ { r : BinaryApp e op e' } =
   let { t, v } = eval ρ e
       { t: t', v: v' } = eval ρ e' in
   case find op ρ of
      Just { u: V.Op φ } -> { t: T.BinaryApp t op t', v: toValues (opFun φ) v v' }
      Just _ -> absurd
      Nothing -> error $ "operator " <> op <> " not found"
-- let
eval ρ { r : Let x e e' } =
   let { t, v } = eval ρ e
       { t: t', v: v' } = eval (ρ :+: x ↦ v) e'
   in { t: T.Let x t t', v: v' }
-- match
eval ρ { r : Match e σ } =
   let { t, v } = eval ρ e
   in case match v σ of
      Nothing -> error "Value mismatch"
      Just (T3 ρ' e' ξ) ->
         let { t: t', v: v' } = eval (ρ <> ρ') e'
         in { t: T.Match t ξ t', v: v' }
