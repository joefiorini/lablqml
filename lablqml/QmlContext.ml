type t

module M = Map.Make(String)

let container: t M.t ref = ref M.empty

let add_view name (v: t) =
  container := M.add name v !container
let () =
  Callback.register "register_view" add_view

let get_view_exn ~name = M.find name !container

let get_view ~name =
  try Some (get_view_exn name)
  with Not_found -> None

type cppobj = [ `cppobject ]
external set_context_property: ctx:t -> name:string -> cppobj -> unit
  = "caml_setContextProperty"

module QPoint = struct
  type t = int*int
  let create x y = (x,y)
  let x = fst
  let y = snd
end

module QVariant = struct
  type t = [ `empty | `string of string | `qobject of cppobj | `int of int | `bool of bool
           | `float of float ]
  let empty = `empty
  let of_string s = `string s
  let of_object o = `qobject o
  let of_int    x = `int x
  let of_bool   b = `bool b
  let of_float  f = `float f
  (*let of_qpoint p = `qpoint p*)
end

module QModelIndex = struct
  type t = int * int
  let empty = (-1,-1)
  let row = fst
  let column = snd
  let make ~row ~column = (row,column)
  let to_string (row,column) = Printf.sprintf "(%d,%d)" row column
end

module QGuiApplication = struct
  type t
  external exec: t -> unit = "caml_QGuiApplication_exec"
end
module QQmlEngine = struct
  type t
  external register_context: name:string -> t -> unit = "caml_QQmlEngine_registerContext"
  external add_import_path: string -> t -> unit = "caml_QQmlEngine_addImportPath"
end
module QQuickWindow = struct
  type t
  external showMaximized: t -> unit = "caml_QQuickWindow_showMaximized"
end

external create_qguiapplication_stub : string array -> QGuiApplication.t * QQmlEngine.t
  = "caml_create_QGuiApplication"
let create_qapplication argv = create_qguiapplication_stub argv

external loadQml_stub: string -> QQmlEngine.t -> QQuickWindow.t option = "caml_loadQml"
let loadQml path engine = loadQml_stub path engine

external run_with_QQmlApplicationEngine_stub : string array -> (unit -> unit) -> string -> unit
  = "caml_run_QQmlApplicationEngine"

(* TODO: add labeled arguments *)
let run_with_QQmlApplicationEngine argv init path = run_with_QQmlApplicationEngine_stub argv init path

type qvariantable
type non_qvariantable

class virtual  ['valtyp] prop (_name:string) = object(self)
  method name = _name
  method virtual get : 'valtyp
  method virtual set : 'valtyp -> unit
end

class virtual ['valtyp] qvariant_prop _name = object (self)
  inherit ['valtyp] prop _name as base
  method virtual wrap_in_qvariant : 'valtyp -> QVariant.t
end

module PropMap: sig
  type t
  val handler: t -> cppobj

  val create: ?callback:(string -> QVariant.t -> unit) -> unit -> t
  val insert: t -> name:string -> QVariant.t -> unit
end = struct
  type t = cppobj

  let handler: t -> cppobj = fun x -> x

  external create_stub: (string -> QVariant.t -> unit) -> unit -> cppobj = "caml_create_QQmlPropertyMap"
  external insert_stub: t -> string -> QVariant.t -> unit = "caml_QQmlPropertyMap_insert"

  let create ?(callback=fun _ _ -> ()) () =
    let (_:string -> QVariant.t -> unit) = callback in
    create_stub callback ()
  let insert map ~name variant = insert_stub map name variant

end
