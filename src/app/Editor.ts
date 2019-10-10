import "../../src/BaseTypes" // otherwise mysterious cyclic initialisation error
import { absurd, as, className, log } from "../util/Core"
import { Expr } from "../Expr"
import { openWithImports } from "../Module"
import { createSvg, svgMetrics, svgNS, textElement, textHeight } from "./Core"
import "./styles.css"

import Trie = Expr.Trie

const fontSize: number = 18,
      class_: string = "code",
      lineHeight: number = log(Math.ceil(textHeight(fontSize, class_, "m")) * 2) // representative character 

// Post-condition: returned element has an entry in "dimensions" map. 
function render (x: number, line: number, e: Expr): SVGElement {
   if (e instanceof Expr.Var) {
      return renderText(x, line, e.x.val)
   } else
   if (e instanceof Expr.Fun) {
      return renderTrie(x, line, e.σ)
   } else
   if (e instanceof Expr.App) {
      return renderHoriz(x, line, e.f, e.e)
   } else {
      return renderText(x, line, `<${className(e)}>`)
   }
}

function renderTrie (x: number, line: number, σ: Trie<Expr>): SVGElement {
   if (Trie.Var.is(σ)) {
      return renderText(x, line, σ.x.val)
   } else
   if (Trie.Constr.is(σ)) {
      return renderText(x, line, `<${className(σ)}>`)
   } else {
      return absurd()
   }
}

function renderHoriz (x: number, line: number, ...es: Expr[]): SVGElement {
   const x0: number = x,
         g: SVGGElement = document.createElementNS(svgNS, "g")
   let height_max: number = 0
   // See https://www.smashingmagazine.com/2018/05/svg-interaction-pointer-events-property/.
   g.setAttribute("pointer-events", "bounding-box")
   for (const e of es) {
      const v: SVGElement = render(x, line, e),
            { width, height }: Dimensions = dimensions.get(v)!
      x += width
      height_max = Math.max(height_max, height)
      g.appendChild(v)
   }
   dimensions.set(g, { width: x - x0, height: height_max })
   return g
}

function renderText (x: number, line: number, str: string): SVGTextElement {
   const text: SVGTextElement = textElement(x, line * lineHeight, fontSize, class_, str)
   svgMetrics.appendChild(text)
   dimensions.set(text, { width: text.getBBox().width, height: lineHeight })
   text.remove()
   return text
}

type Dimensions = { width: number, height: number }

// Populate this explicity, rather than using a memoised function.
const dimensions: Map<SVGElement, Dimensions> = new Map()

class Editor {
   constructor () {
      // Wait for fonts to load before rendering, otherwise metrics will be wrong.
      window.onload = (ev: Event): void => {
         const root: SVGSVGElement = createSvg(400, 400, false),
         polygon: SVGPolygonElement = document.createElementNS(svgNS, "polygon")
         polygon.setAttribute("points", "0, 0 0, 100 100, 0, 100, 100")
         polygon.setAttribute("stroke", "black")
         polygon.setAttribute("fill", "gray")
         root.appendChild(polygon)
         document.body.appendChild(root)
         const e: Expr = as(openWithImports("foldr_sumSquares"), Expr.Defs).e
         root.appendChild(render(0, 0, e))
      }
   }
}

new Editor()
