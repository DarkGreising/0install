(* Copyright (C) 2013, Thomas Leonard
 * See the README file for details, or visit http://0install.net.
 *)

open Support.Common
open Zeroinstall.General
open OUnit
module Stores = Zeroinstall.Stores
module Fetch = Zeroinstall.Fetch
module Recipe = Zeroinstall.Recipe
module F = Zeroinstall.Feed
module Q = Support.Qdom

let download_impls fetcher impls =
  match fetcher#download_impls impls |> Lwt_main.run with
  | `success -> ()
  | `aborted_by_user -> assert false

let impl_template = F.({
  qdom = ZI.make_root "implementation";
  props = {
    attrs = F.AttrMap.singleton ("", "id") "test1"
      |> F.AttrMap.add ("", "version") "1.0"
      |> F.AttrMap.add ("", "from-feed") (Test_0install.feed_dir +/ "test.xml");
    requires = [];
    bindings = [];
    commands = StringMap.empty;
  };
  stability = Testing;
  os = None;
  machine = None;
  parsed_version = Zeroinstall.Versions.parse_version "1.0";
  impl_type = CacheImpl {
    digests = [("sha1", "123")];
    retrieval_methods = [];
  };
})

let parse_xml s =
  let s = "<root xmlns='http://zero-install.sourceforge.net/2004/injector/interface'>" ^ s ^ "</root>" in
  let root = `String (0, s) |> Xmlm.make_input |> Q.parse_input None in
  List.hd root.Q.child_nodes

let suite = "fetch">::: [
  "download-local">:: Fake_system.with_fake_config (fun (config, _fake_system) ->
    let driver = Fake_system.make_driver config in
    let fetcher = driver#fetcher in
    download_impls fetcher [];

    Fake_system.assert_error_contains "(no download locations given in feed!)"
      (fun () -> download_impls fetcher [impl_template]);

    let try_with ?(template = impl_template) ?(digest=("sha1new", "123")) xml =
      let recipe = parse_xml xml in
      let impl_type = F.(CacheImpl {
        digests = [digest];
        retrieval_methods = [recipe];
      }) in
      let impl = F.({template with impl_type}) in
      download_impls fetcher [impl] in

    Fake_system.assert_raises_safe "Missing attribute 'dest' on <file> (generated)" @@
      lazy (try_with "<file href='mylib-1.0.jar'/>");

    let attrs = F.(impl_template.props.attrs |> AttrMap.add ("", "from-feed") "http://example.com/feed.xml") in
    let remote_impl = F.({impl_template with props = {impl_template.props with attrs}}) in
    Fake_system.assert_raises_safe "Relative URL 'mylib-1.0.jar' in non-local feed 'http://example.com/feed.xml'" @@
      lazy (try_with ~template:remote_impl "<file href='mylib-1.0.jar' dest='lib/mylib.jar' size='100'/>");

    Fake_system.assert_raises_safe "Relative URL 'mylib-1.0.zip' in non-local feed 'http://example.com/feed.xml'" @@
      lazy (try_with ~template:remote_impl "<archive href='mylib-1.0.zip' size='100'/>");

    Fake_system.assert_error_contains "tests/mylib-1.0.jar' does not exist"
      (fun () -> try_with "<file href='mylib-1.0.jar' dest='lib/mylib.jar' size='100'/>");

    Fake_system.assert_error_contains "feed says 100, but actually 321 bytes"
      (fun () -> try_with "<file href='HelloWorld.zip' dest='lib/mylib.jar' size='100'/>");

    Fake_system.assert_error_contains "Required digest: sha1new=123"
      (fun () -> try_with "<file href='HelloWorld.zip' dest='lib/mylib.jar' size='321'/>");

    try_with ~digest:("sha1new", "9db418be7ccca3cfd12649ca2822cb618c166e1e") "<file href='HelloWorld.zip' dest='lib/mylib.jar' size='321'/>";

    try_with ~digest:("sha1new", "290eb133e146635fe37713fd58174324a16d595f") "<archive href='HelloWorld.zip' size='321'/>";

    Fake_system.assert_error_contains "Path /lib/mylib.jar is absolute!"
      (fun () -> try_with "<file href='HelloWorld.zip' dest='/lib/mylib.jar' size='321'/>");

    Fake_system.assert_error_contains "Illegal path '.'"
      (fun () -> try_with "<file href='HelloWorld.zip' dest='.' size='321'/>");

    Fake_system.assert_error_contains "Illegal path ''"
      (fun () -> try_with "<file href='HelloWorld.zip' dest='' size='321'/>");

    Fake_system.assert_error_contains "Found '..' in path 'foo/..' - disallowed"
      (fun () -> try_with "<file href='HelloWorld.zip' dest='foo/..' size='321'/>");

    Fake_system.assert_error_contains "Found '..' in path 'foo/..' - disallowed"
      (fun () -> try_with "<file href='HelloWorld.zip' dest='foo/..' size='321'/>");

    let try_recipe ?digest ?error xml =
      try
        try_with ?digest @@ "<recipe><archive href='recipe-base.tgz' extract='recipe' size='305'/>" ^ xml ^ "</recipe>";
        assert (error = None);
      with Safe_exception (msg, _) ->
        let error = error |? lazy (raise_safe "Unexpected error '%s'" msg) in
        if not (Str.string_match (Str.regexp error) msg 0) then (
          raise_safe "Expected error '%s' but got '%s'" error msg
        ) in

    try_recipe ~digest:("sha1new", "d025d1e5c68d349f8106002e821968a5832ff008") "<rename source='rootfile' dest='somefile'/>";
    try_recipe ~error:".*disallowed" "<rename source='../somefile' dest='somefile'/>";
    try_recipe ~error:".*disallowed" "<rename source='rootfile' dest='../somefile'/>";
    try_recipe ~error:"Path /usr/bin/gpg is absolute!" "<rename source='/usr/bin/gpg' dest='gpg'/>";
    try_recipe ~error:"Path /tmp/rootfile is absolute!" "<rename source='rootfile' dest='/tmp/rootfile'/>";

    try_recipe ~digest:("sha1new", "a9415b8f35ceb4261fd1d3dc93c9514876cd817a") "<rename source='rootfile' dest='dir1/rootfile'/>";
    try_recipe ~error:"Refusing to follow non-file non-dir item.*tmp'$" "<rename source='rootfile' dest='tmp/surprise'/>";
    try_recipe ~error:"Refusing to follow non-file non-dir item.*bin'$" "<rename source='bin/gpg' dest='gpg'/>";
    try_recipe ~error:"<rename> source '.*missing-source' does not exist" "<rename source='missing-source' dest='dest'/>";

    try_recipe ~digest:("sha1new", "266fdd7055606c28b299ddc77902b81d500ce946") "<remove path='rootfile'/>";
    try_recipe ~error:"Illegal path '\\.'" "<remove path='.'/>";
  );

  "local-archive">:: Fake_system.with_fake_config (fun (config, fake_system) ->
    let driver = Fake_system.make_driver config in
    let fetcher = driver#fetcher in

    let local_iface = Test_0install.feed_dir +/ "LocalArchive.xml" in
    let root = Q.parse_file config.system local_iface in
    let feed = F.parse config.system root (Some local_iface) in

    let check ?error ?testfile id =
      try
        let impl = StringMap.find id feed.F.implementations in
        let digests =
          match impl.F.impl_type with
          | F.CacheImpl {F.digests; _} -> digests
          | _ -> assert false in

        (* Not cached before download... *)
        assert (Stores.lookup_maybe config.system digests config.stores = None);

        download_impls fetcher [impl];
        assert (error = None);

        match testfile with
        | None -> ()
        | Some testfile ->
            (* Is cached now *)
            let path = Stores.lookup_maybe config.system digests config.stores |? lazy (failwith "missing!") in
            assert (config.system#file_exists (path +/ testfile));
      with Safe_exception (msg, _) ->
        let error = error |? lazy (raise_safe "Unexpected error '%s'" msg) in
        if not (Str.string_match (Str.regexp error) msg 0) then (
          raise_safe "Expected error '%s' but got '%s'" error msg
        ) in

    fake_system#set_argv @@ Array.of_list [
      Test_0install.test_0install; "select"; "--offline"; "--command="; "--xml"; local_iface
    ];
    let xml =
      Fake_system.capture_stdout (fun () ->
        Main.main config.system
      ) in

    let sels = `String (0, xml) |> Xmlm.make_input |> Q.parse_input None in
    assert (Zeroinstall.Selections.get_unavailable_selections config ~distro:driver#distro sels <> []);

    check ~error:"Local file '.*tests/IDONTEXIST.tgz' does not exist" "impl2";
    check ~error:"Wrong size for .*/tests/HelloWorld.tgz: feed says 177, but actually 176 bytes" "impl3";
    check ~testfile:"HelloWorld" "impl1";
    check ~testfile:"archive.tgz" "impl4";
  );

  "url-join">:: fun () -> (
    let test expected base rel =
      Fake_system.assert_str_equal expected @@ Support.Urlparse.join_url base rel in
    test "http://example.com/archive.tgz" "http://example.com/feeds/feed.xml" "/archive.tgz";
    test "http://example.com/feeds/archive.tgz" "http://example.com/feeds/feed.xml" "archive.tgz";
    test "http://example.com/archive.tgz" "http://example.com/feeds/feed.xml" "../archive.tgz";
    test "http://example.com/../archive.tgz" "http://example.com/feeds/feed.xml" "../../archive.tgz";
    test "https://example.com/archive.tgz" "https://example.com/feeds/feed.xml" "//example.com/archive.tgz";
    test "http://foo.com/archive.tgz" "https://example.com/feeds/feed.xml" "http://foo.com/archive.tgz";
    test "http://example.com/archive.tgz" "http://example.com" "archive.tgz";
    test "http://example.com/archive.tgz" "http://example.com" "/archive.tgz";
    test "http://example.com/archive.tgz?q=2" "http://example.com/?q=1/base/" "archive.tgz?q=2";
  )
]