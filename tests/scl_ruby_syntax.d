module tests.scl_ruby_syntax;

import core.stdc.stdio : fprintf, stderr;
import core.stdc.string : strcmp;
import waifucad.scl.ruby_syntax : WC_SCL_LINE, normaliseRubyStyleLine;

private bool expect(const(char)* source, const(char)* expected) nothrow @nogc
{
    char[WC_SCL_LINE] output;
    if (!normaliseRubyStyleLine(source, output.ptr, output.length))
    {
        fprintf(stderr, "Normalisation failed: %s\n", source);
        return false;
    }
    if (strcmp(output.ptr, expected) != 0)
    {
        fprintf(stderr, "Unexpected normalisation:\n  source:   %s\n  expected: %s\n  actual:   %s\n",
                source, expected, output.ptr);
        return false;
    }
    return true;
}

extern(C) int main()
{
    if (!expect("box(:body, 80.mm, 50.mm, 10.mm)".ptr, "box body 80 50 10".ptr)) return 10;
    if (!expect("param(:width, 80.mm)".ptr, "param width 80 mm".ptr)) return 11;
    if (!expect("param angle = 45.deg".ptr, "param angle 45 deg".ptr)) return 12;
    if (!expect("width = 96".ptr, "var width 96".ptr)) return 13;
    if (!expect("puts(\"hello world\")".ptr, "echo \"hello world\"".ptr)) return 14;
    if (!expect("require(\"library.wcs\")".ptr, "use \"library.wcs\"".ptr)) return 15;
    if (!expect("def(:twice, 1, \"calc $result $1 * 2\")".ptr,
                "function twice 1 \"calc $result $1 * 2\"".ptr)) return 16;
    if (!expect("if true then puts(\"ok\") end".ptr, "if true puts \"ok\"".ptr)) return 17;
    if (!expect("for i in 0..2 do puts(i) end".ptr, "for i 0 1 2 puts i".ptr)) return 18;
    if (!expect("set(:width, 96)".ptr, "set width 96".ptr)) return 19;
    if (!expect("echo(part2.mm)".ptr, "echo part2.mm".ptr)) return 20;
    if (!expect("param(:small, -0.5.mm)".ptr, "param small -0.5 mm".ptr)) return 21;
    if (!expect("kind = get_feature_kind(:body)".ptr, "get_feature_kind kind body".ptr)) return 22;
    if (!expect("count = get_feature_count()".ptr, "get_feature_count count".ptr)) return 23;
    if (!expect("name = get_feature_name(i)".ptr, "get_feature_name name i".ptr)) return 24;
    if (!expect("face_id = get_feature_face_persistent_id(:body, i)".ptr,
                "get_feature_face_persistent_id face_id body i".ptr)) return 25;
    if (!expect("surface = get_topology_face_surface_kind(face_id)".ptr,
                "get_topology_face_surface_kind surface face_id".ptr)) return 26;
    return 0;
}


