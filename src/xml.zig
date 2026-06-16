pub const c = @cImport({
    @cInclude("libxml/HTMLparser.h");
    @cInclude("libxml/parser.h");
    @cInclude("libxml/xpath.h");
});
