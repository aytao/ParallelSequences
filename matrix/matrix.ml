open Seq
open Sequence
open Quicksort

let compare_int_tuple (row1, col1 : int * int) (row2, col2 : int * int) = 
  let cmp_r = compare row1 row2 in
  if cmp_r = 0 then compare col1 col2 else cmp_r

module IntTuple : Map.OrderedType with type t = (int * int) =
struct
  type t = (int * int)

  let compare = compare_int_tuple
end

module type MatrixElt =
sig
  type t
  val b : t
  val add : t -> t -> t
  val mul : t -> t -> t
end

module DictOfKeys = Map.Make(IntTuple)

module type MATRIX =
sig
  type elt
  type vect
  type matrix
  val of_dok : int -> int -> elt DictOfKeys.t -> matrix
  val of_elt_arr : ((int * int) * elt) array -> int -> int -> matrix
  val of_2d_arr : elt array array -> matrix
  val get : int -> int -> matrix -> elt
  val dimensions : matrix -> int * int
  val transpose: matrix -> matrix

  val vect_of_array : elt array -> vect
  val vect_mul : matrix -> vect -> vect
  val matrix_mul : matrix -> matrix -> matrix
end

let check_index row col m n s =
  if row < 0 || row >= m || col < 0 || col >= n then
    raise (Invalid_argument s)

let check_size_nonzero m n s =
  if m <= 0 || n <= 0 then raise (Invalid_argument s)

let bin_search nth s compare i lo hi =
  let rec helper lo hi =
    if hi <= lo then -1
    else
      let mid = lo + (hi - lo / 2) in
      let v = nth s mid in
      let cmp = compare v i in
      if cmp < 0 then helper (mid + 1) hi
      else if cmp > 0 then helper lo mid
      else mid
  in
  helper lo hi

let sort_elt_seq sort elt_seq =
  let cmp (tup1, _) (tup2, _) =
    compare_int_tuple tup1 tup2
  in
  sort cmp elt_seq

module ArrayMatrix(E: MatrixElt) : (MATRIX with type elt = E.t) = struct
  type elt = E.t
  type vect = elt array
  type matrix = elt array array
  let b = E.b
  
  let of_dok m n map =
    let _ = check_size_nonzero m n "ArrayMatrix.of_map" in
    let mat = Array.init m (fun i -> Array.make n b) in
    let update_matrix k v =
      let row, col = k in
      let _ = check_index row col m n "ArrayMatrix.of_map" in
      mat.(row).(col) <- v
    in
    DictOfKeys.iter update_matrix map;
    mat
  
  let of_elt_arr (elt_arr: ((int * int) * elt) array) m n =
    let _ = check_size_nonzero m n "ArrayMatrix.of_map" in
    let mat = Array.init m (fun i -> Array.make n b) in
    let update_matrix elt =
      let (row, col), v = elt in
      let _ = check_index row col m n "ArrayMatrix.of_map" in
      mat.(row).(col) <- v
    in
    Array.iter update_matrix elt_arr;
    mat

  let of_2d_arr (elt_arr_arr: elt array array) =
    Array.init (Array.length elt_arr_arr) (fun i -> Array.copy elt_arr_arr.(i))

  let get row col mat =
    let _ = check_index row col (Array.length mat) (Array.length mat.(0)) "ArrayMatrix.get" in
    mat.(row).(col)
  
  let dimensions mat = Array.length mat, Array.length mat.(0)

  let dot v1 v2 =
    assert (Array.length v1 = Array.length v2);
    let acc = ref b in
    for i = 0 to (Array.length v1 - 1) do
      acc := E.add !acc (E.mul v1.(i) v2.(i))
    done;
    !acc

  let transpose mat =
    Array.init (Array.length mat.(0)) (fun i -> Array.init (Array.length mat) (fun j -> mat.(j).(i)))

  let vect_of_array arr =
    Array.copy arr
  
  let vect_mul mat vect =
    let m, n = dimensions mat in
    let len = Array.length vect in
    if n != len then raise (Invalid_argument "ArrayMatrix.vect_mul") else
      (* TODO: Fix redundant length *)
    Array.init (Array.length mat) (fun i -> dot mat.(i) vect)
  
  let matrix_mul mat1 mat2 =
    let m1, n1 = dimensions mat1 in
    let m2, n2 = dimensions mat2 in
    if n1 != m2 then raise (Invalid_argument "ArrayMatrix.matrix_mul") else
    let mat2T = transpose mat2 in
    let resultT = Array.init n2 (fun i -> vect_mul mat1 mat2T.(i)) in
    transpose resultT
end

module SeqMatrix(E: MatrixElt) : (MATRIX with type elt = E.t) = struct
  type elt = E.t
  type vect = elt S.t
  type matrix = elt S.t S.t
  let b = E.b
  
  let of_dok m n map =
    let _ = check_size_nonzero m n "SeqMatrix.of_map" in
    S.tabulate (fun i -> 
      S.tabulate (fun j ->
        if DictOfKeys.mem (i, j) map then DictOfKeys.find (i, j) map else b
      ) n  
    ) m

  let of_elt_arr (elt_arr: ((int * int) * elt) array) m n =
    let elt_seq = sort_elt_seq quicksort (S.seq_of_array elt_arr) in
    let get_val row col =
      let cmp (tup1, _) (tup2, _) =
        compare_int_tuple tup1 tup2
      in
      let tup = ((row, col), b) in
      let idx = bin_search S.nth elt_seq cmp tup 0 (S.length elt_seq) in
      if idx < 0 then b
      else
        let (_, elt) = S.nth elt_seq idx in
        elt
    in
    S.tabulate (fun i -> 
      S.tabulate (fun j ->
        get_val i j
      ) n  
    ) m

  let of_2d_arr (eaa: elt array array) =
    S.tabulate (fun i -> 
      S.tabulate (fun j ->
        eaa.(i).(j)
      ) (Array.length eaa.(i))  
    ) (Array.length eaa)

  let get row col mat =
    let _ = check_index row col (S.length mat) (S.length (S.nth mat 0)) "SeqMatrix.get" in
    S.nth (S.nth mat row) col
  
  let dimensions mat = 
    S.length mat, S.length (S.nth mat 0)

  let dot v1 v2 =
    assert (S.length v1 = S.length v2);
    S.tabulate (fun i -> E.mul (S.nth v1 i) (S.nth v2 i)) (S.length v1)
    |> S.reduce E.add b

  let transpose mat =
    S.tabulate (fun i ->
      S.tabulate (fun j ->
        S.nth (S.nth mat j) i
      ) (S.length mat)
    ) (S.length (S.nth mat 0)) 
  
  let vect_of_array = S.seq_of_array
  
  let vect_mul mat vect =
    (* TODO: Check dim *)
    S.tabulate (fun i -> dot (S.nth mat i) vect) (S.length mat)
  
  let matrix_mul mat1 mat2 =   
    let m1, n1 = dimensions mat1 in
    let m2, n2 = dimensions mat2 in
    if n1 != m2 then raise (Invalid_argument "SeqMatrix.matrix_mul") else
    let mat2T = transpose mat2 in
    let resultT = S.tabulate (fun i -> vect_mul mat1 (S.nth mat2T i)) n2 in
    transpose resultT
end

module CRSMatrix(E: MatrixElt) : (MATRIX with type elt = E.t) = struct
  type elt = E.t
  type vect = elt S.t
  type matrix = {elts: elt S.t; cols: int S.t; row_ptrs: int S.t; m: int; n: int}
  let b = E.b

  let of_elt_seq (s: ((int * int) * elt) S.t) m n =
    let s = sort_elt_seq quicksort s in
    let elts = S.map (fun ((_, _), e) -> e) s in
    let cols = S.map (fun ((_, c), _) -> c) s in

    let inject ((r, _), _) = S.tabulate (fun i -> if i = r then 1 else 0) m in
    let combine counts1 counts2 =
      S.tabulate (fun i -> (S.nth counts1 i + S.nth counts2 i)) m
    in
    let zeros = S.tabulate (fun i -> 0) m in
    let row_counts = S.map_reduce inject combine zeros s in
    let row_ptrs = S.cons 0 (S.scan (+) 0 row_counts) in
    {elts; cols; row_ptrs; m; n}
  
  let of_elt_arr (elt_arr: ((int * int) * elt) array) m n =
    of_elt_seq (S.seq_of_array elt_arr) m n

  let of_dok m n map =
    let _ = check_size_nonzero m n "CRSMatrix.of_map" in
    let s = S.seq_of_array @@ Array.of_list @@ DictOfKeys.bindings map in
    of_elt_seq s m n

  let of_2d_arr (eaa: elt array array) =
    failwith "Unimplemented"

  let get row col {elts; cols; row_ptrs; m; n} =
    let _ = check_index row col m n "CRSMatrix.get" in
    let row_start, row_end = S.nth row_ptrs row, S.nth row_ptrs (row + 1) in
    let row_idx = bin_search S.nth cols Int.compare col row_start row_end in
    if row_idx < 0 then b else S.nth elts (row_start + row_idx)
  
  let dimensions mat = 
    mat.m, mat.n

  let transpose {elts; cols; row_ptrs; m; n} =
    let repeat_row row =
      let row_size = S.nth row_ptrs (row + 1) - S.nth row_ptrs row in
      S.tabulate (fun _ -> row) row_size
    in
    let rows = S.flatten (S.tabulate repeat_row m) in
    let zip i =
      (S.nth cols i, S.nth rows i), S.nth elts i
    in
    let list = S.tabulate zip (S.length elts) in
    of_elt_seq list n m
    
  let vect_of_array = S.seq_of_array

  let vect_mul {elts; cols; row_ptrs; m; n} vect =
    let len = S.length vect in
    if n != len then raise (Invalid_argument "CRSMatrix.vect_mul") else
    let row_body row =
      let row_start, row_end = S.nth row_ptrs row, S.nth row_ptrs (row + 1) in
      S.tabulate (fun i ->
        let idx = i + row_start in
        S.nth cols idx, S.nth elts idx
      ) (row_end - row_start)
    in
    let row_tuple_seqs = S.tabulate row_body m in
    let row_dot row_seq =
      S.map_reduce (fun (c, e) -> E.mul e (S.nth vect c)) E.add b row_seq
    in
    S.map row_dot row_tuple_seqs
  
  let matrix_mul mat1 mat2 = 
    failwith "Unimplemented"
end

module BlockMatrix(E: MatrixElt) : (MATRIX with type elt = E.t) = struct
  type elt = E.t
  type vect = elt S.t
  type matrix = elt S.t S.t
  type submatrix = {
    elts: matrix;
    row_start: int;
    col_start: int;
    m: int;
    n: int;
  }

  type submat_addend = Full of elt array array | Empty
  let b = E.b
  
  let of_dok m n map =
    let _ = check_size_nonzero m n "BlockMatrix.of_map" in
    S.tabulate (fun i -> 
      S.tabulate (fun j ->
        if DictOfKeys.mem (i, j) map then DictOfKeys.find (i, j) map else b
      ) n  
    ) m

  let of_elt_arr (elt_arr: ((int * int) * elt) array) m n =
    let elt_seq = sort_elt_seq quicksort (S.seq_of_array elt_arr) in
    let get_val row col =
      let cmp (tup1, _) (tup2, _) =
        compare_int_tuple tup1 tup2
      in
      let tup = ((row, col), b) in
      let idx = bin_search S.nth elt_seq cmp tup 0 (S.length elt_seq) in
      if idx < 0 then b
      else
        let (_, elt) = S.nth elt_seq idx in
        elt
    in
    S.tabulate (fun i -> 
      S.tabulate (fun j ->
        get_val i j
      ) n  
    ) m

  let of_2d_arr (eaa: elt array array) =
    S.tabulate (fun i -> 
      S.tabulate (fun j ->
        eaa.(i).(j)
      ) (Array.length eaa.(i))  
    ) (Array.length eaa)

  let get row col mat =
    let _ = check_index row col (S.length mat) (S.length (S.nth mat 0)) "BlockMatrix.get" in
    S.nth (S.nth mat row) col
  
  let dimensions mat = 
    S.length mat, S.length (S.nth mat 0)

  let dot v1 v2 mul add b =
    assert (S.length v1 = S.length v2);
    S.tabulate (fun i -> mul (S.nth v1 i) (S.nth v2 i)) (S.length v1)
    |> S.reduce add b

  let transpose mat =
    S.tabulate (fun i ->
      S.tabulate (fun j ->
        S.nth (S.nth mat j) i
      ) (S.length mat)
    ) (S.length (S.nth mat 0)) 
  
  let vect_of_array = S.seq_of_array
  
  let vect_mul mat vect =
    (* TODO: Check dim *)
    S.tabulate (fun i -> dot (S.nth mat i) vect E.mul E.add b) (S.length mat)

  let submatrix_get row col {elts; row_start; col_start; m; n} =
    let _ = check_index row col m n "BlockMatrix.submatrix_get" in
    S.nth (S.nth elts (row_start + row)) (col_start + col)

  let submatrix_mul sm1 sm2 =
    let m, p = sm1.m, sm1.n in
    let p', n = sm2.m, sm2.n in
    if p != p' then raise (Invalid_argument "BlockMatrix.matrix_mul") else
    let body r c =
      let acc = ref b in
      for i = 0 to (p - 1) do
        acc := E.add !acc (E.mul (submatrix_get r i sm1) (submatrix_get i c sm2)) 
      done;
      !acc
    in
    let elts' = Array.init m (fun i ->
      Array.init n (body i)
      ) in
    Full elts'
  
  let eaa_add eaa1 eaa2 =
    let dim eaa = Array.length eaa, Array.length eaa.(0) in
    assert (dim eaa1 = dim eaa2);
    let m, n = dim eaa1 in 
    Array.init m (fun i ->
      Array.init n (fun j ->
        E.add eaa1.(i).(j) eaa2.(i).(j)))

  let submat_add sa1 sa2 =
    match sa1, sa2 with
    | Empty, _ -> sa2
    | _, Empty -> sa1
    | Full (elts1), Full (elts2) ->
      Full (eaa_add elts1 elts2)
  
  let matrix_mul mat1 mat2 =
    let m, p = dimensions mat1 in
    let p', n = dimensions mat2 in
    if p != p' then raise (Invalid_argument "BlockMatrix.matrix_mul") else
    let ceil_div num den = (num + den - 1) / den in
    let submat_size = Defines.sequential_cutoff in
    let num_secs i = ceil_div i submat_size in
    let m_secs = num_secs m in
    let p_secs = num_secs p in
    let n_secs = num_secs n in
    let blocks_of_mat mat num_rows num_cols = S.tabulate (fun i ->
      S.tabulate (fun j ->
        let m, n = dimensions mat in
        let m' = if i = m_secs - 1 then m mod submat_size else submat_size in
        let n' = if j = n_secs - 1 then n mod submat_size else submat_size in
        { 
          elts = mat;
          row_start = i * submat_size;
          col_start = j * submat_size;
          m = m';
          n = n';
        }
      ) num_cols
    ) num_rows
    in
    let bm1 = blocks_of_mat mat1 m_secs p_secs in
    let bm2 = blocks_of_mat mat2 p_secs n_secs in
    let body i j =
      S.tabulate (fun k ->
        let bm1_i = S.nth bm1 i in
        submatrix_mul (S.nth bm1_i k) (S.nth (S.nth bm2 k) j) 
        ) p_secs
        |> S.reduce submat_add Empty 
    in
    let bres = S.tabulate (fun i ->
          S.tabulate (body i) n_secs
      ) m_secs
    in
    S.tabulate (fun i ->
      S.tabulate (fun j ->
          let row_num, col_num = i / submat_size, j / submat_size in
          let row_off, col_off = i mod submat_size, j mod submat_size in
          let block = S.nth (S.nth bres row_num) col_num in
          match block with
          | Full block -> block.(row_off).(col_off)
          | Empty -> failwith "Impossible"
        ) n
      ) m
end