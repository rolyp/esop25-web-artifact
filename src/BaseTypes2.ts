import { Explainable, Fun, Value, make } from "./ExplVal2"

export abstract class List<T> extends Explainable<List<T>> {
   abstract __match<U> (σ: ListFun<T, U>): U
}

export class Nil<T> extends List<T> {
   __match<U> (σ: ListFun<T, U>): U {
      return σ.Nil()
   }
}

export function nil<T> (): List<T> {
   return make(Nil, {})
}

export class Cons<T extends Value> extends List<T> {
   head: T
   tail: List<T>

   __match<U> (σ: ListFun<T, U>): U {
      return σ.Cons(this.head, this.tail)
   }
}

export function cons<T extends Value> (head: T, tail: List<T>): List<T> {
   return make(Cons, { head, tail })
}

abstract class ListFun<T, U> extends Fun<U> {
   abstract Nil (): U
   abstract Cons (x: T, xs: List<T>): U
}

export class Pair<T, U> extends Explainable<Pair<T, U>> {
   fst: T
   snd: U

   __match<V> (σ: PairFun<T, U, V>): V {
      return σ.Pair(this.fst, this.snd)
   }
}

interface PairFun<T, U, V> extends Fun<V> {
   Pair (fst: T, snd: U): V
}

export abstract class Tree<T> extends Explainable<Tree<T>> {
   abstract __match<U> (σ: TreeFun<T, U>): U
}

export class Empty<T> extends Tree<T> {
   __match<U> (σ: TreeFun<T, U>): U {
      return σ.Empty()
   }
}

export class NonEmpty<T> extends Tree<T> {
   left: Tree<T>
   t: T
   right: Tree<T>

   __match<U> (σ: TreeFun<T, U>): U {
      return σ.NonEmpty(this.left, this.t, this.right)
   }
}

interface TreeFun<T, U> extends Fun<U> {
   Empty (): U
   NonEmpty (left: Tree<T>, t: T, right: Tree<T>): U
}
