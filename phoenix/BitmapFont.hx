package phoenix;

import luxe.Vector;
import luxe.resource.Resource;
import luxe.resource.ResourceManager;

import phoenix.Batcher;
import phoenix.BitmapFont.TextAlign;
import phoenix.geometry.CompositeGeometry;
import phoenix.geometry.Geometry;
import phoenix.geometry.QuadGeometry;
import phoenix.geometry.TextureCoord;
import phoenix.geometry.Vertex;
import phoenix.Rectangle;
import phoenix.Texture;

import luxe.Log.log;
import luxe.Log._debug;
import luxe.Log._verbose;

enum TextAlign {
    left;
    right;
    center;
    top;
    bottom;
}

typedef Character = {
    var id : Int;
    var x : Float;
    var y : Float;
    var width : Float;
    var height : Float;
    var xoffset : Float;
    var yoffset : Float;
    var xadvance : Float;
    var page : Int;
}

typedef KerningKey = {
    var glyph : Int;
    var index : Int;
}

//this is not the best option
typedef KeyValuePair = {
    var key : String;
    var value : String;
}

typedef PageInfo = {
    id : Int,
    file : String
}

class BitmapFont extends Resource {

        //  _font_name:String = '', _bitmap_file : String = ''
    public var dimensions : Vector;
    public var spacing : Float = 0.0;
    public var line_height : Float = 0.0;
    public var font_size : Float = 0.0;
    public var font_character_count : Int = 0;
    public var pages : Map<Int, Texture>;
    public var characters : Map<Int, Character>;
    public var kernings : Map< KerningKey, Float >;
    public var scale : Vector;
    public var on_pages_loaded : Void -> Void;
    public var pages_loaded : Int = 0;
    public var onload : BitmapFont -> Void;

    var line_widths : Array<Float>;

    public function new( ?_resource_manager : ResourceManager = null ) {

        super( _resource_manager, ResourceType.font);

        id  = 'Unnamed font';

        line_widths = new Array<Float>();
        dimensions = new Vector();
        characters = new Map();
        kernings = new Map();
        scale = new Vector(1,1);
        pages = new Map();

        on_pages_loaded = on_all_pages_loaded;

    }

    function toString() {
        return "BitmapFont(" + id + ")";
    }


    public static function load( _fontid:String, ?_path:String = 'assets/', ?_onloaded:BitmapFont->Void ) : BitmapFont {

            //:todo: which resource manager...
        var new_font = new BitmapFont( Luxe.resources );
        var font_data = Luxe.loadText( haxe.io.Path.join([_path, _fontid]) );

            new_font.from_string( font_data.text, _path, _onloaded );

            Luxe.resources.cache(new_font);

        return new_font;

    } //load

    function _tokenize_font_line(_line_tokens:Array<String>) {
        var _item_map : Map<String, KeyValuePair> = new Map();
        for(_line_token in _line_tokens) {
            var _items = _line_token.split("=");
            _item_map.set( _items[0], { key:_items[0], value:_items[1] } );
        }
        return _item_map;
    }

    public function on_all_pages_loaded() {
        if(onload != null) {
            onload( this );
        }
    }

    public function one_page_loaded(t:Texture) {
        pages_loaded++;
        if(pages_loaded == Lambda.count(pages)) {
            on_all_pages_loaded();
        }
    }

    public function from_string( _bitmap_file : String = '',
                                      _folder : String = 'assets/',
                                      ?onloaded : BitmapFont->Void = null,
                                      ?custom_pages:Array<Texture> = null ) {

        var lines : Array<String> = _bitmap_file.split("\n");
        var _pages : Array<PageInfo> = [];

            //store the listener
        onload = onloaded;

        for(line in lines) {
            var _initial_tokens = line.split(" ");
            switch (_initial_tokens[0]) {

                case "info":

                    _initial_tokens.remove("info");
                    var _items = _tokenize_font_line(_initial_tokens);

                    var _id = _items["face"].value;
                    if(_id.indexOf('"') != -1) {
                        _id = StringTools.replace(_id,'"', '');
                    }

                        //font size value for scale later
                    font_size = Std.parseFloat(_items["size"].value);

                    id = _id;

                case "common":

                    _initial_tokens.remove("common");
                    var _items = _tokenize_font_line(_initial_tokens);

                            //parse the line height
                        line_height = Std.parseFloat( _items["lineHeight"].value );
                        // font_size = Std.parseFloat(_items["base"].value);

                case "page":

                    _initial_tokens.remove("page");
                    var _items = _tokenize_font_line(_initial_tokens);

                            //parse the page info
                        var _id = Std.parseInt( _items["id"].value );
                        var _file = _items["file"].value;

                            //remove arbitrary quotes ""
                        if(_file.indexOf('"') != -1) {
                            _file = StringTools.replace(_file,'"', '');
                        }

                            //remove arbitrary new lines
                        _file = StringTools.trim( _file );

                            //Store the texture id's in the list
                        _pages.push({ id:_id, file:_file });
                            //Set this so the count is maintained
                        pages.set(_id, null);

                case "chars":

                    _initial_tokens.remove("chars");
                    var _items = _tokenize_font_line(_initial_tokens);

                            //parse the character count
                        font_character_count = Std.parseInt( _items["count"].value );

                case "char":

                    _initial_tokens.remove("char");
                    var _items = _tokenize_font_line(_initial_tokens);

                    //parse character info
                    var _character_info : Character = {
                        id : Std.parseInt(_items["id"].value),
                        x : Std.parseFloat(_items["x"].value),
                        y : Std.parseFloat(_items["y"].value),
                        width : Std.parseFloat(_items["width"].value),
                        height : Std.parseFloat(_items["height"].value),
                        xoffset : Std.parseFloat(_items["xoffset"].value),
                        yoffset : Std.parseFloat(_items["yoffset"].value),
                        xadvance : Std.parseFloat(_items["xadvance"].value),
                        page : Std.parseInt(_items["page"].value)
                    };

                    set_character(_character_info.id, _character_info);

                case "kerning":

                    _initial_tokens.remove("char");
                    var _items = _tokenize_font_line(_initial_tokens);

                        var first = Std.parseInt(_items["first"].value);
                        var second = Std.parseInt(_items["second"].value);
                        var amount = Std.parseFloat(_items["amount"].value);

                        set_kerning( first, second, amount );

            } //switch
        } //line in lines

        //once all loaded, we can load up the pages textures
        //but only if the custom pages wasn't specified
        if(custom_pages == null) {

            for(_page_item in _pages) {
                    //fetch the texture
                var _t = Luxe.loadTexture( _folder + _page_item.file, one_page_loaded );
                    //store the texture in the map for use
                _t.onload = function(t_t) {
                    pages.set(_page_item.id, _t);
                    // _t.generate_mipmaps();
                    _t.filter_min = FilterType.linear;
                    // _t.filter_mag = FilterType.linear;
                }

            }

        } else {

            var _id : Int = 0;

            for(_page in custom_pages) {
                pages.set(_id, _page);
                ++_id;
            } //for each custom page

                //still do the callback in case
            on_all_pages_loaded();

        } //if custom pages

    } //from_string

    public function set_kerning(_glyph:Int, _index:Int, _amount:Float) {
        kernings.set({ glyph:_glyph, index:_index}, _amount);
    }

    public function get_kerning(_glyph:Int, _index:Int) {
        var key = { glyph:_glyph, index:_index };
        if(kernings.exists(key)) {
            return kernings.get(key);
        } else {
            return 0;
        }
    }

        //return the size of a piece of text for this font, at the given scale
    public function get_text_dimensions(_string:String, _scale:Vector) {

            // Set up variables
            //line_widths caches the sizes for quicker renderering in a loop
        line_widths.splice(0, line_widths.length);

            //for calculating the entire size
        var cumulative_x : Float = 0.0;
        var cumulative_y : Float = 0.0;
        var max_x : Float = 0.0;
        var spc = characters[(' ').charCodeAt(0)];

            //Iterate over each character, calculating size

        for( i in 0 ... _string.length) {

            var glyph = _string.charAt(i);

            if( glyph == '\n' ){
                cumulative_y += line_height * _scale.y;
                max_x = Math.max( max_x, cumulative_x );
                line_widths.push(cumulative_x);
                cumulative_x = 0;
                continue;
            }

            var c = characters[ glyph.charCodeAt(0) ];

            // var _x : Float = cumulative_x + ( c.xoffset * _scale.x );
            // var _y : Float = cumulative_y + ( c.yoffset * _scale.y );
            // var _w : Float = c.width * _scale.x;
            // var _h : Float = c.height * _scale.y;
            var _x_advance : Float = 0.0;
            if(c != null) {
                _x_advance = c.xadvance;
            }

                //adjust culmative x value
            var x_inc : Float = _x_advance;
            if( i < _string.length - 1 ){
                x_inc += get_kerning( glyph.charCodeAt(0), _string.charAt(i).charCodeAt(0) );
            }

            if( glyph == '\t' ){
                x_inc += spc.xadvance * 4;
            }

            cumulative_x += x_inc * _scale.x;

        } //for each char

            //account for the last line/only line
        line_widths.push(cumulative_x);
        max_x = Math.max( max_x, cumulative_x );

            //Add one line of height. We do this because we want the
            //total height and the culmative y is (at this point)
            //the y at the *top* of the last line.
        cumulative_y += line_height * _scale.y;

        return new Vector( max_x, cumulative_y );
    }


    public function draw_text( options : Dynamic ) {

         var _string : String = (options.text == null) ? Std.string("") : Std.string(options.text);
         var _pos: Vector = (options.pos == null) ? new Vector() : options.pos;
         var _col: Color = (options.color == null) ? new Color() : options.color;
         var _bounds: Rectangle = (options.bounds == null) ? null : options.bounds;
         var _align: TextAlign = (options.align == null) ? TextAlign.left : options.align;
         var _valign: TextAlign = (options.align_vertical == null) ? TextAlign.top : options.align_vertical;
         var _depth: Float = (options.depth == null) ? 0 : options.depth;
         var _size : Float = (options.size == null) ? 22 : options.size;
         var _batcher : Batcher = (options.batcher == null) ? Luxe.renderer.batcher : options.batcher;
         var _visible : Bool = (options.visible == null) ? true : options.visible;
         var _immediate : Bool = (options.immediate == null) ? false : options.immediate;
         var _final_geom = (options.geometry == null) ? new CompositeGeometry(null) : options.geometry;

         var _bounds_based : Bool = false;
         if(_bounds != null) {
            _bounds_based = true;
         }

            //no texture? return empty geometry
        if(pages[0] == null) {
            log("Warning ; " + id + " font trying to draw without a texture.");
            return _final_geom;
        }

            //an array of geometry items, one for each unique texture
        var _geoms : Array<Geometry> = new Array<Geometry>();
        var _page_count = Lambda.count(pages);

        _verbose('creating geometry for each unique texture : ' + _page_count + ' at ' + _depth + '\n with ' + _col + ' and ' + _align + ' and at ' + _pos );

        for(i in 0 ... _page_count ) {

            var _g = new Geometry({
                texture : pages[i],
                color : _col,
                depth : _depth,
                visible : _visible,
                immediate : _immediate
            });

            _g.id = 'text.page'+i+'.'+_string;//.substr(0,8);

            _g.primitive_type = PrimitiveType.triangles;
            _g.immediate = _immediate;
            _geoms.push( _g );

        } //for each page

            //so, the font is a %
        var point_size : Float = _size/font_size;
        // point_size = luxe.utils.Maths.fixed(point_size, 3);
        var _scale : Vector = new Vector(point_size,point_size);

        if(!_immediate) {
            // trace('$_string font_size:$font_size    size:$_size    point_size:$point_size');
        }

        var _cumulative_x : Float = 0.0;
        var _cumulative_y : Float = 0.0;

            //a cached size of a space, if we need it
        var spc = characters[(' ').charCodeAt(0)];

        var _line_number : Int = 0;
        var _dimensions : Vector = get_text_dimensions(_string, _scale);
        var _max_line_width : Float = _dimensions.x;

        var _lines = _string.split('\n');

        for(_line in _lines) {

            var _align_x_offset : Float = 0.0;

                //Calculate alignment position
                //Left is at 0, so it's handled already
            if( _align == TextAlign.center ) {
                _align_x_offset = (_max_line_width/2.0) - (line_widths[_line_number]/2.0);
            } else
            if( _align == TextAlign.right ) {
                _align_x_offset = _max_line_width - line_widths[_line_number];
            }

                //if not the first line, add height
            if( _line_number != 0 ){
                _cumulative_y += line_height * _scale.y;
                _cumulative_x = 0;
            }

            for(i in 0 ... _line.length) {

                var _char = _line.charAt(i);
                var c = characters[ _char.charCodeAt(0) ];

                if(c == null) {
                    //hmm, a null character code?
                    //probably insert a black block or something?
                    c = spc;
                }

                    //find the geometry to add it to
                var _geom = _geoms[c.page];

                    //Texture size for this page
                var _tw = pages[c.page].width_actual;
                var _th = pages[c.page].height_actual;

                    //work out the coordinates for the uv's
                var _u  : Float = c.x/_tw;
                var _v  : Float = c.y/_th;
                var _u2 : Float = (c.x + c.width) / _tw;
                var _v2 : Float = (c.y + c.height) / _th;
                var _x  : Float = _align_x_offset + _cumulative_x + ( c.xoffset * _scale.x );
                var _y  : Float = _cumulative_y + c.yoffset * _scale.y;
                var _w  : Float = c.width * _scale.x;
                var _h  : Float = c.height * _scale.y;

                var _x_inc : Float = c.xadvance;
                if( i < _line.length-1 ){
                    _x_inc += get_kerning( c.id, _char.charCodeAt(0) );
                }

                if( _char == '\t' ){
                    _x_inc += spc.xadvance * 4; //:todo:, hardcoded 4 tab size
                }

                _cumulative_x += _x_inc * _scale.x;

                // _x = Math.round(_x);
                // _y = Math.round(_y);

                    //First triangle

               var vert0 : Vertex = new Vertex( new Vector( _x, _y ), _col );
                   vert0.uv.uv0.set_uv(_u,_v);

                var vert1 : Vertex = new Vertex( new Vector( _x+_w, _y ), _col );
                   vert1.uv.uv0.set_uv(_u2, _v);

                var vert2 : Vertex = new Vertex( new Vector( _x+_w, _y+_h ), _col );
                    vert2.uv.uv0.set_uv(_u2, _v2);

                   //Second triangle

                var vert3 : Vertex = new Vertex( new Vector( _x, _y+_h ), _col );
                    vert3.uv.uv0.set_uv(_u, _v2);

                var vert4 : Vertex = new Vertex( new Vector( _x, _y ), _col );
                    vert4.uv.uv0.set_uv(_u, _v);

                var vert5 : Vertex = new Vertex( new Vector( _x+_w, _y+_h), _col );
                    vert5.uv.uv0.set_uv(_u2, _v2);

                   //Add to the geomery

                _geom.add( vert0 ); _geom.add( vert1 );  _geom.add( vert2 );
                _geom.add( vert3 ); _geom.add( vert4 );  _geom.add( vert5 );

            } //for each string

                //next line (if any)
            _line_number++;

        } //line in lines

            //replace the composite with the children geometry we just created
        _final_geom.replace( _geoms );
        _final_geom.add_to_batcher(_batcher);

        if(!_bounds_based) {

                //translate all of the new text according to the alignment alignment
            var _po = _pos.clone();

            if( _align == TextAlign.center ) {
                _po.x = _pos.x - (_max_line_width/2);
            } else if( _align == TextAlign.right ) {
                _po.x = _pos.x - (_max_line_width);
            }
                //translate all of the new text according to the actual position
            _final_geom.transform.origin = new Vector( _pos.x-_po.x, _pos.y-_po.y );
            _final_geom.transform.pos = _pos.clone();

        } else {

                //translate all of the new text according to the alignment alignment
            var _po = new Vector(_bounds.x, _bounds.y);

            if( _align == TextAlign.center ) {
                _po.x = _po.x + ((_bounds.w/2) - (_dimensions.x/2));
            } else if( _align == TextAlign.right ) {
                _po.x = _po.x + ((_bounds.w) - (_dimensions.x));
            }

            if( _valign == TextAlign.center ) {
                _po.y = _po.y + ((_bounds.h/2) - (_dimensions.y/2));
            } else if( _valign == TextAlign.bottom ) {
                _po.y = _po.y + ((_bounds.h) - (_dimensions.y));
            }
                //translate all of the new text according to the actual position
            _final_geom.transform.origin = new Vector( _pos.x-_po.x, _pos.y-_po.y );
            _final_geom.transform.pos = _pos.clone();


        } //_bounds_based

        // _verbose('drew text ${_string.substr(0,10)} at ${_final_geom.transform.pos} with origin ${_final_geom.transform.origin}');

        _final_geom.id = 'drawn_text- ' + _string.substr(0,10);
        // _final_geom.transform.id = 'drawn_text- ' + _string.substr(0,10);
        _final_geom.immediate = _immediate;
        _final_geom.visible = _visible;

        return _final_geom;

    }

    public function set_character( _index:Int,  _char_info : Character ) {
        characters.set( _index, _char_info);
    }
}
