import { ann } from "../util/Annotated"
import { __nonNull, as } from "../util/Core"
import { List } from "../BaseTypes"
import { emptyEnv } from "../Env"
import { Eval } from "../Eval"
import { ExplValue } from "../ExplValue"
import { Expr } from "../Expr"
import { GraphicsElement } from "../Graphics"
import { Value } from "../Value"
import { setallα } from "../Versioned"
import { load, parse } from "../../test/util/Core"
import { Cursor } from "../../test/util/Cursor"
import { Data, DataView, DataRenderer } from "./DataRenderer"
import { GraphicsPane3D } from "./GraphicsPane3D"
import { GraphicsRenderer } from "./GraphicsRenderer"

class App {
   e: Expr                        // entire closed program
   tv: ExplValue                  // chart computed by program
   data_e: Expr                   // expression for data (value bound by first let in user code)
   data_tv: ExplValue             // value of data
   dataView: DataView
   dataCanvas: HTMLCanvasElement
   dataCtx: CanvasRenderingContext2D
   graphicsCanvas: HTMLCanvasElement
   graphicsPane3D: GraphicsPane3D
   svg: SVGSVGElement
   
   constructor () {
      this.svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
      this.svg.setAttribute("width", "200")
      this.svg.setAttribute("height", "200")
      document.body.appendChild(this.svg)

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

   // "Data" is defined to be the value of the first let statement in user code, which must be a /closed/
   // expression. This allows us to run it "out of context" and evaluate/slice it independently of the rest
   // of the program.
   initData (): void {
      const here: Cursor = new Cursor(this.e)
      here.skipImports().toDef("data").to(Expr.Let, "e")
      this.data_e = as(here.v, Expr.Constr)
      this.data_tv = Eval.eval_(emptyEnv(), this.data_e)
      setallα(this.data_e, ann.top)
      Eval.eval_fwd(this.data_tv)
   }

   get data (): Data {
      return as(this.data_tv.v as Value, List)
   }

   get graphics (): GraphicsElement {
      return as(this.tv.v as Value, GraphicsElement)
   }
   
   loadExample (): void {
      this.e = parse(load("bar-chart"))
      this.tv = Eval.eval_(emptyEnv(), this.e)
      this.initData()
      setallα(this.e, ann.top)
      Eval.eval_fwd(this.tv)
      this.renderData(this.data)
      this.draw()
   }

   // Push annotations back from data to source, then redo the forward slice.
   redoFwdSlice (): void {
      setallα(this.data_e, ann.bot)
      // TODO: clear annotations on intermediate values somehow
      Eval.eval_bwd(this.data_tv)
      Eval.eval_fwd(this.tv)
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
            this.redoFwdSlice()
         }
      })
      this.dataCanvas.height = this.dataView.height + 1 // why extra pixel needed?
      this.dataCanvas.width = this.dataView.width
   }

   renderGraphics (g: GraphicsElement): void {
      new GraphicsRenderer(this.graphicsCanvas, this.svg).render(g)
   }
}

new App()
