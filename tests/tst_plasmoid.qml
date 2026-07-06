import QtQuick
import QtTest
import "../package/contents/ui/ShellQuote.js" as ShellQuote

TestCase {
    name: "KClaude"

    function test_shellQuote_escapes_embedded_single_quotes() {
        compare(ShellQuote.shellQuote("it's a test"), "'it'\\''s a test'");
    }

    function test_shellQuote_wraps_plain_uuid() {
        compare(ShellQuote.shellQuote("d06f16b7-15e1-463f-88ab-8ffaee7a492e"),
                "'d06f16b7-15e1-463f-88ab-8ffaee7a492e'");
    }
}
