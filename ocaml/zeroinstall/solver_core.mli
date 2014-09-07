(* Copyright (C) 2014, Thomas Leonard
 * See the README file for details, or visit http://0install.net.
 *)

(** Select a compatible set of components to run a program. *)

module Make : functor (Model : Solver_types.MODEL) -> sig
  type diagnostics

  class type result =
    object
      method get_selections : (Model.Role.t * Model.impl * string list) list

      (* The remaining methods are used to provide diagnostics *)
      method get_selected : Model.Role.t -> Model.impl option
      method implementations : (Model.Role.t * (diagnostics * Model.impl) option) list
    end

  val do_solve : Model.t -> Model.Role.t -> ?command:string -> closest_match:bool -> result option

  (** Request diagnostics-of-last-resort (fallback used when [Diagnostics] can't work out what's wrong).
   * Gets a report from the underlying SAT solver. *)
  val explain : diagnostics -> string
end
