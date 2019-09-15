import { __nonNull } from "../../src/util/Core"
import { ann } from "../../src/util/Lattice"
import { setallα } from "../../src/Annotated"
import { ExplValue } from "../../src/DataValue"
import { Env, emptyEnv } from "../../src/Env"
import { Eval } from "../../src/Eval"
import { Expr } from "../../src/Expr"
import { clearDelta, clearMemo } from "../../src/Value"
import "../../src/Graphics" // for graphical datatypes
import { Cursor, ExplCursor } from "../../src/app/Cursor"
import "../../src/app/GraphicsRenderer" // for graphics primitives

// Key idea here is that we never push slicing further back than ρ (since ρ could potentially
// be supplied by a library function, dataframe in another language, or other resource which
// lacks source code).

export class FwdSlice {
   expr: Cursor

   constructor (e: Expr, ρ: Env = emptyEnv()) {
      clearMemo()
      setallα(ann.top, e)
      setallα(ann.top, ρ)
      this.expr = new Cursor(e)
      const tv: ExplValue = Eval.eval_(ρ, e)
      Eval.eval_fwd(e, tv) // slice with full availability first to compute delta
      clearDelta()
      this.setup()
      if (flags.get(Flags.Fwd)) {
         Eval.eval_fwd(e, tv)
         this.expect(new ExplCursor(tv))
      }
      console.log(e)
      console.log(tv)
   }

   setup (): void {
   }

   expect (here: ExplCursor): void {
   }
}

export class BwdSlice {
   expr: Cursor

   constructor (e: Expr, ρ: Env = emptyEnv()) {
      if (flags.get(Flags.Bwd)) {
         clearMemo()
         setallα(ann.bot, e)
         setallα(ann.bot, ρ)
         const tv: ExplValue = Eval.eval_(ρ, e) // to obtain tv
         Eval.eval_fwd(e, tv) // clear annotations on all values
         clearDelta()
         this.setup(new ExplCursor(tv))
         Eval.eval_bwd(e, tv)
         this.expr = new Cursor(e)
         this.expect()
      }
   }

   setup (here: ExplCursor): void {
   }

   expect (): void {      
   }
}

enum Flags { Bwd, Fwd }
const flags: Map<Flags, boolean> = new Map([
   [Flags.Fwd, true],
   [Flags.Bwd, true]
])
