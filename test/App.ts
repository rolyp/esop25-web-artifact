import * as THREE from "three"
import { OrbitControls } from "three-orbitcontrols-ts"
import * as Meshline from "three.meshline"
import { __nonNull, assert, make } from "../src/util/Core"
import { InternedObject } from "../src/Runtime"
import { Cons, List, Nil } from "../src/BaseTypes"
import { Traced, Value } from "../src/Traced"
import { TestFile, initialise, loadTestFile, runTest } from "../test/Helpers"

class Rect {
   x: number
   y: number
   width: number
   height: number

   constructor (x: number, y: number, width: number, height: number) {
      this.x = x
      this.y = y
      this.width = width
      this.height = height
   }

   object3D (): THREE.Object3D {
      const geometry: THREE.Geometry = new THREE.Geometry
      geometry.vertices.push(new THREE.Vector3(this.x, this.y, 0))
      geometry.vertices.push(new THREE.Vector3(this.x + this.width, this.y, 0))
      geometry.vertices.push(new THREE.Vector3(this.x + this.width, this.y + this.height, 0))
      geometry.vertices.push(new THREE.Vector3(this.x, this.y + this.height, 0))
      geometry.faces.push(new THREE.Face3(0,1,2))
      geometry.faces.push(new THREE.Face3(2,3,0))
      return new THREE.Mesh(
         geometry, 
         new THREE.MeshBasicMaterial({ color: 0xF6831E, side: THREE.DoubleSide })
      )
   }
}

class Point extends InternedObject { // for now
   x: number
   y: number

   constructor (x: number, y: number) {
      super()
      this.x = x
      this.y = y
   }

   static make (x: number, y: number): Point {
      return make(Point, x, y)
   }
}

function path_object3D (points: List<Point>): THREE.Object3D {
   const geometry: THREE.Geometry = new THREE.Geometry
   while (Cons.is(points)) {
      geometry.vertices.push(new THREE.Vector3(points.head.x, points.head.y, 0))
      points = points.tail
   }
   return new THREE.Line(geometry, new THREE.LineBasicMaterial({ 
      color: 0x000000 
   }))
}

initialise()
const file: TestFile = loadTestFile("example", "bar-chart")
const [rects, paths]: [Rect[], List<Point>[]] = getRectsPaths(__nonNull(runTest(__nonNull(file.text))))

export function getRectsPaths (tv: Traced): [Rect[], List<Point>[]] {
   if (tv.v instanceof Value.Constr) {
      if (tv.v.ctr.str === "Pair") {
         const rects_axes: List<Traced> = tv.v.args
         if (Cons.is(rects_axes) && Cons.is(rects_axes.tail)) {
            return [getRects(rects_axes.head), getPaths(rects_axes.tail.head)]
         }
      }
   }
   return assert(false)
}

export function getRects (tv: Traced): Rect[] {
   if (tv.v instanceof Value.Constr) {
      if (tv.v.ctr.str === "Cons") {
         const rect_tvs: List<Traced> = tv.v.args
         if (Cons.is(rect_tvs) && Cons.is(rect_tvs.tail)) {
            return [getRect(rect_tvs.head)].concat(getRects(rect_tvs.tail.head))
         } 
      } else
      if (tv.v.ctr.str === "Nil" && Nil.is(tv.v.args)) {
         return []
      }
   }
   return assert(false)
}

function getRect (tv: Traced): Rect {
   __nonNull(tv.v)
   if (tv.v instanceof Value.Constr && tv.v.ctr.str === "Rect") {
      const tvs: List<Traced> = tv.v.args
      if (Cons.is(tvs) && tvs.head.v instanceof Value.ConstInt && 
          Cons.is(tvs.tail) && tvs.tail.head.v instanceof Value.ConstInt &&
          Cons.is(tvs.tail.tail) && tvs.tail.tail.head.v instanceof Value.ConstInt && 
          Cons.is(tvs.tail.tail.tail) && tvs.tail.tail.tail.head.v instanceof Value.ConstInt) {
         return new Rect(
            tvs.head.v.val,
            tvs.tail.head.v.val,
            tvs.tail.tail.head.v.val,
            tvs.tail.tail.tail.head.v.val
         )
      } 
   }
   return assert(false)
}

export function getPaths (tv: Traced): List<Point>[] {
   if (tv.v instanceof Value.Constr) {
      if (tv.v.ctr.str === "Cons") {
         const points_tvs: List<Traced> = tv.v.args
         if (Cons.is(points_tvs) && Cons.is(points_tvs.tail)) {
            return [getPath(points_tvs.head)].concat(getPaths(points_tvs.tail.head))
         } 
      } else
      if (tv.v.ctr.str === "Nil" && Nil.is(tv.v.args)) {
         return []
      }
   }
   return assert(false)
}

export function getPath (tv: Traced): List<Point> {
   if (tv.v instanceof Value.Constr) {
      if (tv.v.ctr.str === "Cons") {
         const point_tvs: List<Traced> = tv.v.args
         if (Cons.is(point_tvs)) {
            const point: Traced = point_tvs.head
            if (point.v instanceof Value.Constr && point.v.ctr.str === "Point") {
               const x_y: List<Traced> = point.v.args
               if (Cons.is(x_y)) {
                  if (x_y.head.v instanceof Value.ConstInt && Cons.is(x_y.tail) &&
                     x_y.tail.head.v instanceof Value.ConstInt && Cons.is(point_tvs.tail)) {
                        return Cons.make(
                           Point.make(x_y.head.v.val, x_y.tail.head.v.val),
                           getPath(point_tvs.tail.head)
                        )
                  }
               }
            }
         } 
      } else
      if (tv.v.ctr.str === "Nil" && Nil.is(tv.v.args)) {
         return Nil.make()
      }
   }
   return assert(false)
}

const scene = new THREE.Scene()
scene.background = new THREE.Color( 0xffffff )
const camera = new THREE.PerspectiveCamera( 60, 1, 1, 200 )
camera.position.set( 0, 0, 100 )
camera.lookAt( new THREE.Vector3(0, 0, 0) )

const renderer = new THREE.WebGLRenderer
renderer.setSize( 600, 600 )

const controls = new OrbitControls( camera, renderer.domElement );

// How far you can orbit vertically, upper and lower limits.
controls.minPolarAngle = 0;
controls.maxPolarAngle = Math.PI;

// How far you can dolly in and out ( PerspectiveCamera only )
controls.minDistance = 0;
controls.maxDistance = Infinity;

controls.enableZoom = true; // Set to false to disable zooming
controls.zoomSpeed = 1.0;

controls.enablePan = true; // Set to false to disable panning (ie vertical and horizontal translations)

controls.enableDamping = true; // Set to false to disable damping (ie inertia)
controls.dampingFactor = 0.25;

document.body.appendChild(renderer.domElement)

export class Path extends THREE.Geometry {
   constructor (path: THREE.Vector2[]) {
      super()   
      for (const point of path) {
         this.vertices.push(new THREE.Vector3(point.x, point.y, 0))
      }
   }

    object3D (): THREE.Object3D {
      return new THREE.Line(this, new THREE.LineBasicMaterial({ 
         color: 0x000000 
      }))
   }
}

export class ThickPath extends THREE.Geometry {
   constructor (path: THREE.Vector2[]) {
      super()   
      for (const point of path) {
         this.vertices.push(new THREE.Vector3(point.x, point.y, 0))
      }
   }

   object3D (): THREE.Object3D {
      const line = new Meshline.MeshLine()
      line.setGeometry(this)
      const material = new Meshline.MeshLineMaterial({
         color: new THREE.Color(0x000000),
         sizeAttenuation: 0,
         lineWidth: 0.020
      })
      return new THREE.Mesh( line.geometry, material )
   }
}

export function close (path: THREE.Vector2[]) {
   return path.concat(path[0])
}

function populateScene (): void {
   for (let rect of rects) {
      scene.add(rect.object3D())
//      scene.add(new Path(close(rect)).object3D())
   }
   for (let path of paths) {
      scene.add(path_object3D(path))
   }
}

function render () {
   renderer.render(scene, camera)
}

controls.addEventListener("change", render)
populateScene()
render()
