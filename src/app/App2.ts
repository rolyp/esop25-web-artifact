import { ann } from "../util/Annotated"
import { __nonNull, as } from "../util/Core"
import { List} from "../BaseTypes2"
import { emptyEnv } from "../Env2"
import { Eval } from "../Eval2"
import { Expl, ExplValue, explValue } from "../ExplValue2"
import { Expr } from "../Expr2"
import { GraphicsElement } from "../Graphics2"
import { Value } from "../Value2"
import { setallα } from "../Versioned2"
import { load, parse } from "../../test/util/Core2"
import { Cursor } from "../../test/util/Cursor2"
import { Data, DataView, DataRenderer } from "./DataRenderer"
import { GraphicsPane3D } from "./GraphicsPane3D"
import { GraphicsRenderer } from "./GraphicsRenderer"
import { reflect, reify } from "./Reflect"

class App {
   e: Expr                          // body of outermost let
   data_e: Expr                     // expression for data (value bound by let)
   data_t: Expl                     // trace for data
   data: Data                       // data reflected up to meta-level
   dataView: DataView
   dataCanvas: HTMLCanvasElement
   dataCtx: CanvasRenderingContext2D
   graphics: GraphicsElement        // chart computed by from data
   graphicsCanvas: HTMLCanvasElement
   graphicsPane3D: GraphicsPane3D
   
   constructor () {
      this.dataCanvas = document.createElement("canvas")
      this.dataCtx = __nonNull(this.dataCanvas.getContext("2d"))
      this.graphicsCanvas = document.createElement("canvas")
      this.graphicsPane3D = new GraphicsPane3D(600, 600)
      this.dataCanvas.style.verticalAlign = "top"
      this.dataCanvas.style.display = "inline-block"
      this.graphicsPane3D.renderer.domElement.style.verticalAlign = "top"
      this.graphicsPane3D.renderer.domElement.style.display = "inline-block"
      document.body.appendChild(this.dataCanvas)
      document.body.appendChild(this.graphicsCanvas)
      // document.body.appendChild(this.graphicsPane3D.renderer.domElement)
      this.graphicsPane3D.setCanvas(this.graphicsCanvas)
      this.graphicsCanvas.width = this.graphicsCanvas.height = 400
      this.loadExample()
   }
   
   loadExample (): void {
      this.e = parse(load("bar-chart"))
      let here: Cursor = new Cursor(this.e)
      here.skipImports().to(Expr.Let, "e")
      this.data_e = as(here.o, Expr.Constr)
      this.fwdSlice()
      this.renderData(this.data)
      this.draw()
   }

   // On passes other than the first, the assignments here are redundant.
   fwdSlice (): void {
      const { t, v: data }: ExplValue = Eval.eval_(prelude, this.data_e)
      this.data_t = t
      this.data = as(reflect(as(data, Value.Constr)), List)
      this.graphics = as(reflect(Eval.eval_(emptyEnv(), this.e).v), GraphicsElement)
   }

   // Push changes from data back to source code, then forward slice.
   redo_fwdSlice (): void {
      setallα(this.data_e, ann.bot)
      Eval.uneval(explValue(emptyEnv(), this.data_t, reify(this.data)))
      this.fwdSlice()
      this.draw()
   }

   draw (): void {
      this.dataCtx.clearRect(0, 0, this.dataCanvas.width, this.dataCanvas.height)
      this.dataView.draw()
      this.renderGraphics(this.graphics) // TODO: adopt same "view" pattern?
      // this.graphicsPane3D.render()
   }

   renderData (data: Data): void {
      this.dataCanvas.height = 400
      this.dataCanvas.width = 400
      this.dataView = new DataRenderer(this.dataCtx, data).view
      this.dataCanvas.addEventListener("mousemove", (e: MouseEvent): void => {
         const rect: ClientRect = this.dataCanvas.getBoundingClientRect()
         if (this.dataView.onMouseMove(e.clientX - rect.left, e.clientY - rect.top)) {
            this.redo_fwdSlice()
         }
      })
      this.dataCanvas.height = this.dataView.height + 1 // not sure why extra pixel is essential
      this.dataCanvas.width = this.dataView.width
   }

   renderGraphics (g: GraphicsElement): void {
      new GraphicsRenderer(this.graphicsCanvas).render(g)
   }
}

new App()
