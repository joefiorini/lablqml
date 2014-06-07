open Ast_mapper
open Ast_helper
open Asttypes
open Parsetree
open Longident
open Location
open Printf

module Ref = struct
  let append ~set x = set := x :: !set
end

let rec has_attr name: Parsetree.attributes -> bool = function
  | [] -> false
  | ({txt;loc},_) :: _ when txt = name  -> true
  | _ :: xs -> false

let getenv s = try Sys.getenv s with Not_found -> ""

exception Error of Location.t
exception Error2 of string * Location.t

let () =
  Location.register_error_of_exn (fun exn ->
    match exn with
    | Error loc ->
      Some (error ~loc " QWE [%getenv] accepts a string, e.g. [%getenv \"USER\"]")
    | Error2 (msg,loc) -> Some (error ~loc msg)
    | _ -> None)

let (_: Ast_mapper.mapper) = default_mapper

let cppobj_coretyp loc =
  Ast_helper.Typ.constr ~loc ({txt=Lident "cppobj"; loc}) []

let make_store_func ~loc ~classname : structure_item =
  let pval_name = {txt="store"; loc} in
  let pval_prim = [sprintf "caml_store_value_in_%s" classname] in
  let pval_type = Ast_helper.Typ.(arrow ""
                                        (cppobj_coretyp loc)
                                        (arrow ""
                                               (object_ ~loc [] Open)
                                               (constr ~loc {txt=Lident "unit"; loc} [] ) ) )
  in
  let pstr_desc = Pstr_primitive {pval_name; pval_type; pval_prim; pval_attributes=[];
                                  pval_loc=loc } in
  { pstr_desc; pstr_loc=loc }

let make_initializer ~loc : class_field =
  let pexp_desc = Ast_helper.Exp.(
    apply (ident (mkloc (Lident "store") loc))
          [ ("",ident (mkloc (Lident "cppobj") loc))
          ; ("",ident (mkloc (Lident "self") loc))
          ]
          )
  in (* TODO: *)
  let pcf_desc = Pcf_initializer pexp_desc in
  { pcf_desc; pcf_loc=loc; pcf_attributes=[] }

let make_handler_meth ~loc : class_field =
  let e = Ast_helper.Exp.(poly (ident (mkloc (Lident "cppobj") loc) ) None) in
  Ast_helper.(Cf.method_ (mkloc "handler" loc) Public (Cfk_concrete (Fresh,e)  ) )

let wrap_meth ~classname (({txt=name;_},_,kind) as m) = [Pcf_method m]
let wrap_prop ~classname (({txt=name;_},_,kind) as v) = [Pcf_method v]

let wrap_class_decl mapper loc _ (ci: Parsetree.class_expr Parsetree.class_infos) =
  (*print_endline "wrap_class_type_decl on class type markend with `qtclass`";*)
  let classname = ci.pci_name.txt in
  let clas_sig = match ci.pci_expr.pcl_desc with
    | Pcl_structure s -> s
    |  _    -> raise (Error2 ("???", ci.pci_loc))
  in
  let fields: class_field list = clas_sig.pcstr_fields in

  let heading = ref [] in
  Ref.append ~set:heading (make_store_func   ~classname ~loc);

  let wrap_field (f_desc: class_field) : class_field list =
    let ans = match f_desc.pcf_desc with
      | Pcf_method m  when has_attr "qtmeth" f_desc.pcf_attributes -> wrap_meth ~classname m
      | Pcf_method m  when has_attr "qtprop" f_desc.pcf_attributes -> wrap_prop ~classname m
      | _ -> []
    in
    let ans' = List.map (fun ans -> { f_desc with pcf_desc=ans }) ans in
    ans'
  in
  let new_fields = List.map wrap_field fields |> List.concat in
  let new_fields = (make_initializer loc) :: (make_handler_meth ~loc) :: new_fields in
  let new_desc = Pcl_structure { pcstr_fields = new_fields;
                                 pcstr_self = Ast_helper.Pat.var (mkloc "self" loc) } in
  let new_expr = {ci.pci_expr with pcl_desc = new_desc } in
  let new_desc2 = Pcl_fun ("", None, Ast_helper.Pat.var (mkloc "cppobj" loc), new_expr) in
  let new_expr2 = {new_expr with pcl_desc = new_desc2 } in

  let ans = { pstr_desc=Pstr_class [{ci with pci_expr=new_expr2}]; pstr_loc=loc } in
  !heading @ [ans]

(*
let (_:int) = Ast_helper.with_default_loc
 *)

let getenv_mapper argv =
  (* Our getenv_mapper only overrides the handling of expressions in the default mapper. *)
  { default_mapper with
    structure = fun mapper items ->
      let rec iter items =
        match items with
        | { pstr_desc=Pstr_class [cinfo]; pstr_loc } as item :: rest when
               has_attr "qtclass" cinfo.pci_attributes ->
           Ast_helper.with_default_loc pstr_loc (fun () ->
             wrap_class_decl mapper pstr_loc item cinfo @ iter rest )
        | { pstr_loc } as item :: rest ->
          mapper.structure_item mapper item :: iter rest
        | [] -> []
      in
      iter items
  }

let () = run_main getenv_mapper
