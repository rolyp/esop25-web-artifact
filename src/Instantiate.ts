import { assert} from "./util/Core"
import { Cons, List, Nil } from "./BaseTypes"
import { Env } from "./Env"
import { Eval } from "./Eval"
import { Expr, Trace, Traced, Trie, Value } from "./Syntax"

export function instantiateList (es: List<Expr.Expr>, ρ: Env): List<Traced> {
   if (Cons.is(es)) {
      return Cons.make(instantiate(es.head, ρ), instantiateList(es.tail, ρ))
   } else
   if (Nil.is(es)) {
      return Nil.make()
   } else {
      return assert(false)
   }
}

export function instantiate (e: Expr.Expr, ρ: Env): Traced {
   const i: Eval.Evaluand = Eval.Evaluand.make(ρ.entries(), e)
   if (e instanceof Expr.ConstInt) {
      return Traced.at(i, Trace.Empty.at(i), Value.ConstInt.at(i, e.val))
   } else
   if (e instanceof Expr.ConstStr) {
      return Traced.at(i, Trace.Empty.at(i), Value.ConstStr.at(i, e.val))
   } else
   if (e instanceof Expr.Constr) {
      return Traced.at(i, Trace.Empty.at(i), Value.Constr.at(i, e.ctr, instantiateList(e.args, ρ)))
   } else
   if (e instanceof Expr.Fun) {
      // No need to use "unknown" environment here because we have ρ.
      // TODO
      return Traced.at(i, Trace.Empty.at(i), Value.Closure.at(i, ρ, instantiateTrie(e.σ, ρ)))
   } else
   if (e instanceof Expr.PrimOp) {
      return Traced.at(i, Trace.Empty.at(i), e.op)
   } else
   if (e instanceof Expr.Var) {
      return Traced.at(i, Trace.Var.at(i, e.ident, null), null)
   } else
   if (e instanceof Expr.OpName) {
      return Traced.at(i, Trace.OpName.at(i, e.opName, null), null)
   } else
   if (e instanceof Expr.Let) {
      return Traced.at(i, Trace.Let.at(i, instantiate(e.e, ρ), instantiate(e.σ.body, ρ).trace!), null)
   } else
   if (e instanceof Expr.LetRec) {
      return Traced.at(i, Trace.LetRec.at(i, e.δ, instantiate(e.e, ρ).trace!), null)
   } else
   if (e instanceof Expr.MatchAs) {
      // Do we want the σ in the match trace?
      return Traced.at(i, Trace.Match.at(i, instantiate(e.e, ρ), null), null)
   } else
   if (e instanceof Expr.App) {
      return Traced.at(i, Trace.App.at(i, instantiate(e.func, ρ), instantiate(e.arg, ρ), null), null)
   } else {
      return assert(false)
   }
}

function instantiateTrie (σ: Trie<Expr>, ρ: Env): Trie<Expr> {
   if (Trie.Var.is(σ)) {
      return Trie.Var.at(i, σ.x, instantiate(σ.body, ρ))
   } else {
      return assert(false)
   }
}
