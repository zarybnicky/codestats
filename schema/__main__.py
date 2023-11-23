#!/usr/bin/env python3

from collections import defaultdict
import fileinput
import itertools
import re
import os
import shutil

type_prefix = {
    "MATERIALIZED VIEW": "mv_",
    "SEQUENCE": "sq_",
    "INDEX": "ix_",
    "TABLE": "tb_",
    "TYPE": "ty_",
    "VIEW": "vw_",
    "FUNCTION": "fn_",
    "SCHEMA": "sc_",
    "RULE": "rl_",
    "CONSTRAINT": "cs_",
    "TRIGGER": "tr_",
    "FK CONSTRAINT": "fk_",
}

source = ""
for line in fileinput.input():
    source += line

per_table = defaultdict(lambda: defaultdict(lambda: []))

for group in re.split(r"^-- Name: ", source, flags=re.MULTILINE)[1:]:
    match = re.search(r"^(?P<name>[^;]+); Type: (?P<type>[^;]+);", group)
    if match is None:
        print(f"Invalid group {group}")
        continue
    object_type = match.group("type")
    name = match.group("name")
    entry = list(map(lambda x: x.strip(), group.split("--")))[1]

    if object_type == "MATERIALIZED VIEW":
        object_type = "VIEW"

    if object_type in (
        "SEQUENCE",
        "SCHEMA",
        "EXTENSION",
        "DEFAULT",
        "SEQUENCE OWNED BY",
        "DEFAULT ACL",
    ):
        continue  # SKIP

    if object_type in ("TABLE", "FUNCTION", "VIEW", "ROW SECURITY", "DOMAIN", "TYPE"):
        per_table[name][object_type].append(entry)
        continue

    if object_type in ("CONSTRAINT", "TRIGGER", "FK CONSTRAINT", "POLICY"):
        policy_target, policy_name = name.split(" ", 1)
        per_table[policy_target][object_type].append(entry)
        continue

    if object_type in ("ACL", "COMMENT"):
        acl_type, acl_target = name.split(" ", 1)

        if acl_type in ("SCHEMA", "SEQUENCE", "EXTENSION"):
            continue

        if acl_type in ("TABLE", "VIEW"):
            per_table[acl_target][object_type].append(entry)
            continue

        if acl_type == "FUNCTION":
            fn_name, fn_arglist = acl_target.rstrip(")").split("(", 1)
            fn_args = []
            for arg in fn_arglist.split(", "):
                if not arg or arg.startswith("OUT "):
                    continue
                if arg.startswith("INOUT "):
                    arg = arg.split(" ", 1)[1]
                fn_args.append(arg.split(" ", 1)[1])
            per_table[f"{fn_name}({', '.join(fn_args)})"][object_type].append(entry)
            continue

        if acl_type == "COLUMN":
            acl_table, acl_column = acl_target.split(".", 1)
            per_table[acl_table][object_type].append(entry)
            continue

    if object_type == "INDEX":
        match = re.search(
            r"CREATE [^.]+\.(?P<table>[^ ]+) .*", group, flags=re.MULTILINE
        )
        if match is None:
            print(f"Invalid group {group}")
            continue
        per_table[match.group("table")][object_type].append(entry)
        continue

    print(f"Not processed {match.group('type')}: {match.group('name')}")

if not os.path.exists("schema"):
    os.makedirs("schema")
if os.path.exists("schema/types"):
    shutil.rmtree("schema/types")
os.makedirs("schema/types")
if os.path.exists("schema/domains"):
    shutil.rmtree("schema/domains")
os.makedirs("schema/domains")
if os.path.exists("schema/tables"):
    shutil.rmtree("schema/tables")
os.makedirs("schema/tables")
if os.path.exists("schema/functions"):
    shutil.rmtree("schema/functions")
os.makedirs("schema/functions")
if os.path.exists("schema/views"):
    shutil.rmtree("schema/views")
os.makedirs("schema/views")

for table_name, objects in per_table.items():
    object_type = "type" if objects["TYPE"] else "view" if objects["VIEW"] else "function" if objects["FUNCTION"] else "table" if objects["TABLE"] else "domain"
    main_object = (objects["VIEW"] + objects["FUNCTION"] + objects["TABLE"] + objects["DOMAIN"] + objects["TYPE"])[0]
    schema = main_object.split('.')[0].split(' ')[-1]
    source = itertools.chain(
        objects["TABLE"],
        objects["FUNCTION"],
        objects["VIEW"],
        objects["DOMAIN"],
        objects["TYPE"],
        [""],
        objects["COMMENT"],
        [""],
        objects["ACL"],
        objects["ROW SECURITY"],
        [""],
        objects["CONSTRAINT"],
        objects["FK CONSTRAINT"],
        [""],
        objects["POLICY"],
        [""],
        objects["TRIGGER"],
        [""],
        objects["INDEX"],
    )
    filename = f"schema/{object_type}s/{schema}.{table_name}.sql"
    with open(filename, "w") as opf:
        opf.write("\n".join(source).replace("\n\n\n", "\n\n").replace("\n\n\n", "\n\n"))
