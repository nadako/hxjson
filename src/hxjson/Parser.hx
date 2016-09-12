package hxjson;

import hxjson.Json;

class Parser {
    public static inline function parse(source:String, filename:String):Json {
        return new Parser(source, filename).parseRec();
    }

    var source:String;
    var filename:String;
    var pos:Int;

    function new(source:String, filename:String) {
        this.source = source;
        this.filename = filename;
        this.pos = 0;
    }

    function parseRec():Json {
        while (true) {
            var c = nextChar();
            switch(c) {
                case ' '.code | '\r'.code | '\n'.code | '\t'.code:
                    // loop
                case '{'.code:
                    var fields = new Array<JObjectField>();
                    var field = null;
                    var fieldPos = null;
                    var comma:Null<Bool> = null;
                    var startPos = pos - 1;
                    while (true) {
                        switch (nextChar()) {
                            case ' '.code | '\r'.code | '\n'.code | '\t'.code:
                                // loop
                            case '}'.code:
                                if (field != null || comma == false)
                                    invalidChar();
                                return {pos: mkPos(startPos, pos), value: JObject(fields)};
                            case ':'.code:
                                if (field == null)
                                    invalidChar();
                                fields.push({
                                    name: field,
                                    namePos: fieldPos,
                                    value: parseRec()
                                });
                                field = null;
                                fieldPos = null;
                                comma = true;
                            case ','.code:
                                if (comma)
                                    comma = false;
                                else
                                    invalidChar();
                            case '"'.code:
                                if (comma)
                                    invalidChar();
                                var fieldStartPos = pos - 1;
                                field = parseString();
                                fieldPos = mkPos(fieldStartPos, pos);
                            default:
                                invalidChar();
                        }
                    }
                case '['.code:
                    var values = [];
                    var comma:Null<Bool> = null;
                    var startPos = pos - 1;
                    while (true) {
                        switch (nextChar()) {
                            case ' '.code | '\r'.code | '\n'.code | '\t'.code:
                                // loop
                            case ']'.code:
                                if (comma == false)
                                    invalidChar();
                                return {pos: mkPos(startPos, pos), value: JArray(values)};
                            case ','.code:
                                if (comma)
                                    comma = false;
                                else
                                    invalidChar();
                            default:
                                if (comma)
                                    invalidChar();
                                pos--;
                                values.push(parseRec());
                                comma = true;
                        }
                    }
                case 't'.code:
                    var save = pos;
                    if (nextChar() != 'r'.code || nextChar() != 'u'.code || nextChar() != 'e'.code) {
                        pos = save;
                        invalidChar();
                    }
                    return {pos: mkPos(save - 1, pos), value: JBool(true)};
                case 'f'.code:
                    var save = pos;
                    if (nextChar() != 'a'.code || nextChar() != 'l'.code || nextChar() != 's'.code || nextChar() != 'e'.code) {
                        pos = save;
                        invalidChar();
                    }
                    return {pos: mkPos(save - 1, pos), value: JBool(false)};
                case 'n'.code:
                    var save = pos;
                    if (nextChar() != 'u'.code || nextChar() != 'l'.code || nextChar() != 'l'.code) {
                        pos = save;
                        invalidChar();
                    }
                    return {pos: mkPos(save - 1, pos), value: JNull};
                case '"'.code:
                    var save = pos;
                    var s = parseString();
                    return {pos: mkPos(save - 1, pos), value: JString(s)};
                case '0'.code, '1'.code,'2'.code,'3'.code,'4'.code,'5'.code,'6'.code,'7'.code,'8'.code,'9'.code,'-'.code:
                    return parseNumber(c);
                default:
                    invalidChar();
            }
        }
    }

    function parseString():String {
        var start = pos;
        var buf = null;
        while (true) {
            var c = nextChar();
            if (c == '"'.code)
                break;
            if (c == '\\'.code) {
                if (buf == null)
                    buf = new StringBuf();
                buf.addSub(source, start, pos - start - 1);
                c = nextChar();
                switch(c) {
                    case "r".code:
                        buf.addChar("\r".code);
                    case "n".code:
                        buf.addChar("\n".code);
                    case "t".code:
                        buf.addChar("\t".code);
                    case "b".code:
                        buf.addChar(8);
                    case "f".code:
                        buf.addChar(12);
                    case "/".code | '\\'.code | '"'.code:
                        buf.addChar(c);
                    case 'u'.code:
                        var uc = Std.parseInt("0x" + source.substr(pos, 4));
                        pos += 4;
                        #if (neko || php || cpp || lua)
                        if (uc <= 0x7F)
                            buf.addChar(uc);
                        else if (uc <= 0x7FF) {
                            buf.addChar(0xC0 | (uc >> 6));
                            buf.addChar(0x80 | (uc & 63));
                        } else if (uc <= 0xFFFF) {
                            buf.addChar(0xE0 | (uc >> 12));
                            buf.addChar(0x80 | ((uc >> 6) & 63));
                            buf.addChar(0x80 | (uc & 63));
                        } else {
                            buf.addChar(0xF0 | (uc >> 18));
                            buf.addChar(0x80 | ((uc >> 12) & 63));
                            buf.addChar(0x80 | ((uc >> 6) & 63));
                            buf.addChar(0x80 | (uc & 63));
                        }
                        #else
                        buf.addChar(uc);
                        #end
                    default:
                        throw "Invalid escape sequence \\" + String.fromCharCode(c) + " at position " + (pos - 1);
                }
                start = pos;
            }
            #if (neko || php || cpp)
            // ensure utf8 chars are not cut
            else if (c >= 0x80) {
                pos++;
                if (c >= 0xFC) pos += 4;
                else if (c >= 0xF8) pos += 3;
                else if (c >= 0xF0) pos += 2;
                else if (c >= 0xE0) pos++;
            }
            #end
            else if (StringTools.isEof(c))
                throw "Unclosed string";
        }
        if (buf == null) {
            return source.substr(start, pos - start - 1);
        } else {
            buf.addSub(source,start, pos - start - 1);
            return buf.toString();
        }
    }

    inline function parseNumber(c:Int):Json {
        var start = pos - 1;
        var minus = c == '-'.code;
        var digit = !minus;
        var zero = c == '0'.code;
        var point = false;
        var e = false;
        var pm = false;
        var end = false;
        while (true) {
            switch (nextChar()) {
                case '0'.code:
                    if (zero && !point)
                        invalidNumber(start);
                    if (minus) {
                        minus = false;
                        zero = true;
                    }
                    digit = true;
                case '1'.code | '2'.code | '3'.code | '4'.code | '5'.code | '6'.code | '7'.code | '8'.code | '9'.code:
                    if (zero && !point)
                        invalidNumber(start);
                    if (minus)
                        minus = false;
                    digit = true;
                    zero = false;
                case '.'.code:
                    if (minus || point)
                        invalidNumber(start);
                    digit = false;
                    point = true;
                case 'e'.code | 'E'.code:
                    if (minus || zero || e)
                        invalidNumber(start);
                    digit = false;
                    e = true;
                case '+'.code | '-'.code:
                    if (!e || pm)
                        invalidNumber(start);
                    digit = false; pm = true;
                default:
                    if (!digit)
                        invalidNumber(start);
                    pos--;
                    end = true;
            }
            if (end)
                break;
        }
        var s = source.substr(start, pos - start);
        return {pos: mkPos(start, pos), value: JNumber(s)};
    }

    inline function nextChar():Int {
        return StringTools.fastCodeAt(source, pos++);
    }

    inline function mkPos(min:Int, max:Int):Position {
        return {file: filename, min: min, max: max};
    }

    function invalidChar() {
        pos--; // rewind
        throw "Invalid char " + StringTools.fastCodeAt(source, pos) + " at position " + pos;
    }

    function invalidNumber(start:Int) {
        throw "Invalid number at position " + start + ": " + source.substr(start, pos - start);
    }
}
