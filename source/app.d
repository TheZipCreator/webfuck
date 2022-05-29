import vibe.vibe;
import std.file;
import std.json;
import std.conv;
import std.algorithm;
import std.stdio;
import std.range;
import std.array;

string root = "public";

void main() {
  JSONValue config = parseJSON(readText("config.json"));
	auto settings = new HTTPServerSettings;
	settings.port = cast(ushort)config["port"].integer;
	settings.bindAddresses = ["::1", "127.0.0.1"];
  root = config["root"].str;
	auto listener = listenHTTP(settings, &getPage);
	scope (exit) {
		listener.stopListening();
	}

	logInfo("Please open http://127.0.0.1:"~to!string(config["port"].integer)~"/ in your browser.");
	runApplication();
}

void getPage(HTTPServerRequest req, HTTPServerResponse res) {
  string path = root~req.requestURI;
	//res.writeBody(path, "text/plain; charset=UTF-8");
  if(std.file.exists(path)) {
    if(std.file.isFile(path)) {
      string content = readText(path);
      string ext = getExt(path);
      switch(ext) {
        case "html":
          content = parsebf(content);
          res.writeBody(content, "text/html; charset=UTF-8");
          break;
        case "css":
          res.writeBody(content, "text/css; charset=UTF-8");
          break;
        case "b":
          res.writeBody(brainfuck(lexer(content)), "text/plain; charset=UTF-8");
          break;
        default:
          res.writeBody(content, "text/plain; charset=UTF-8");
      }
    } else {
      if(std.file.exists(path~"index.html")) {
        string content = readText(path~"index.html");
        content = parsebf(content);
        res.writeBody(content, "text/html; charset=UTF-8");
      } else {
        res.writeBody("Error 404: The resource at path "~path~" could not be found.", "text/plain");
      }
    }
  } else {
    res.writeBody("Error 404: The resource at path "~path~" could not be found.", "text/plain");
  }
}

string getExt(string path) {
  for(int i = (cast(int)path.length)-1; i >= 0; i--) {
    if(path[i] == '.') {
      return path[(i+1) .. $];
    }
  }
  return "";
}

// string parsebf(string file) {
//   while(count(file, "<?bf") > 0) {
//     long start = countUntil(file, "<?bf");
//     long end = countUntil(file[start .. $], "?>")+start+2;
//     string code = file[start+4 .. end-2];
//     try {
//       string result = brainfuck(lexer(code));
//       file = file[0 .. start]~result~file[end .. $];
//     } catch(BrainfuckException e) {
//       file = file[0 .. start]~"<b>Webfuck Error: </b>"~e.msg~file[end .. $];
//       return file;
//     }
//   }
//   return file;
// }

string parsebf(string file) {
  long start;
  long end = 0;
  string o = "";
  while(count(file, "<?bf") > 0) {
    start = countUntil(file, "<?bf");
    o ~= "#echo \""~escape(file[end .. start])~"\"\n";
    file = file[0 .. start]~"\0"~file[start+1 .. $]; //replace <?bf with \0?bf, not a good solution but works
    end = countUntil(file[start .. $], "?>")+start+2;
    o ~= file[start+4 .. end-2];
  }
  o ~= "#echo \""~escape(file[end .. $])~"\"";
  try {
    return brainfuck(lexer(o));
  } catch(BrainfuckException e) {
    return readText("error.html").replace("%ERROR%", e.msg);
  }
  //return o;
}

string escape(string str) {
  string o = "";
  for(int i = 0; i < str.length; i++) {
    char c = str[i];
    switch(c) {
      case '\\':
        o ~= "\\\\";
        break;
      case '"':
        o ~= "\\\"";
        break;
      default:
        o ~= c;
    }
  }
  return o;
}

const enum TOKENS {
  BF_COMMAND = 0,
  DIRECTIVE = 1,
  EOF = 2
}

struct Token {
  int type;
  string value;
  this(int type, string value) {
    this.type = type;
    this.value = value;
  }
}

Token[] lexer(string code) {
  Token[] tokens;
  int state = 0;
  string value = "";
  for(int i = 0; i < code.length; i++) {
    char c = code[i];
    if(c == '\r') continue; //I hate carriage returns I hate carriage returns I hate carriage returns 
    //write(c~" "~to!string(state)~"|");
    final switch(state) {
      case 0: //default
        switch(c) {
          case '>':
          case '<':
          case '+':
          case '-':
          case '[':
          case ']':
          case '.':
          case ',':
            tokens ~= Token(TOKENS.BF_COMMAND, to!string(c));
            break;
          case ';':
            state = 1; //comment
            break;
          case '#':
            state = 2; //directive
            break;
          default:
            break;
        }
        break;
      case 1: //comment
        if(c == '\n') state = 0;
        break;
      case 2: //directive
        switch(c) {
          case '\n':
            state = 0;
            tokens ~= Token(TOKENS.DIRECTIVE, value);
            value = "";
            break;
          case '"':
            value ~= '"';
            state = 3;
            break;
          default:
            value ~= c;
        }
        break;
      case 3: //in quotes
        switch(c) {
          case '\\':
            state = 4;
            break;
          case '"':
            state = 2;
            value ~= '"';
            break;
          default:
            value ~= c;
        }
        break;
      case 4: //escape
        value ~= "\\"~c;
        state = 3;
        break;
    }
  }
  tokens ~= Token(TOKENS.EOF, "");
  return tokens;
}

string[] parseDirective(string directive) {
  string[] output;
  int state = 0;
  string value = "";
  for(int i = 0; i < directive.length; i++) {
    char c = directive[i];
    final switch(state) {
      case 0:
        switch(c) {
          case '"':
            state = 1;
            break;
          case ' ':
            output ~= value;
            value = "";
            break;
          case '\n':
            break;
          default:
            value ~= c;
        }
        break;
      case 1:
        switch(c) {
          case '\\':
            state = 2;
            break;
          case '"':
            state = 0;
            break;
          default:
            value ~= c;
        }
        break;
      case 2:
        value ~= c;
        state = 1;
        break;
    }
  }
  if(value.length > 0) output ~= value;
  return output;
}

string brainfuck(Token[] tokens) {
  // writeln("======");
  // for(int i = 0; i < tokens.length; i++) {
  //   writeln("TYPE: "~to!string(tokens[i].type));
  //   writeln("VALUE: "~tokens[i].value);
  // }
  string stdout = "";
  int[] tape;
  int[] stdin;
  int head;
  tape ~= 0;
  for(int i = 0; i < tokens.length; i++) {
    Token t = tokens[i];
    int type = t.type;
    string value = t.value;
    final switch(type) {
      case TOKENS.BF_COMMAND:
        switch(value) {
          case ">":
            head++;
            if(head > tape.length-1) tape ~= 0;
            break;
          case "<":
            head--;
            if(head < 0) throw new BrainfuckException("Head out of bounds");
            break;
          case "+":
            tape[head]++;
            break;
          case "-":
            tape[head]--;
            break;
          case "[":
            if(tape[head] == 0) {
              int bracket = 1;
              while(bracket != 0) {
                i++;
                if(tokens[i].value == "[" && tokens[i].type == TOKENS.BF_COMMAND) bracket++;
                else if(tokens[i].value == "]" && tokens[i].type == TOKENS.BF_COMMAND) bracket--;
                if(i > tokens.length-1) throw new BrainfuckException("Unbalanced bracket");
              }
            }
            break;
          case "]":
            if(tape[head] != 0) {
              int bracket = 1;
              while(bracket != 0) {
                i--;
                if(tokens[i].value == "[" && tokens[i].type == TOKENS.BF_COMMAND) bracket--;
                else if(tokens[i].value == "]" && tokens[i].type == TOKENS.BF_COMMAND) bracket++;
                if(i < 0) throw new BrainfuckException("Unbalanced bracket");
              }
            }
            break;
          case ".":
            stdout ~= cast(char)tape[head];
            break;
          case ",":
            if(stdin.length > 0) {
              tape[head] = stdin[0];
              stdin.popFront();
            } else {
              tape[head] = -1;
            }
            break;
          default:
            //do nothing
            break;
        }
        break;
      case TOKENS.DIRECTIVE: {
        string[] args = parseDirective(value);
        switch(args[0]) {
          case "in": {
            if(args.length > 2) throw new BrainfuckException("Too many arguments supplied to in");
            string path = root~"/"~args[1];
            if(std.file.exists(path)) {
              ubyte[] data = cast(ubyte[])std.file.read(path);
              for(int j = 0; j < data.length; j++) stdin ~= to!int(data[j]);
            } else {
              throw new BrainfuckException("Resource "~path~" could not be located");
            }
            break;
          }
          case "echo":
            if(args.length > 2) throw new BrainfuckException("Too many arguments supplied to echo");
            stdout ~= args[1];
            break;
          case "save": {
            if(args.length > 2) throw new BrainfuckException("Too many arguments supplied to save");
            ubyte[] data;
            for(int j = 0; j < tape.length; j++) {
              int x = tape[j];
              data ~= (cast(ubyte*) &x)[0 .. x.sizeof]; //convert into to ubyte[]. I don't know how this works I stole it from dlang forum
            }
            string path = root~"\\"~args[1];
            //string path = root~"\\test.bin";
            if(std.file.exists(path)) {
              if(isDir(path)) throw new BrainfuckException("Invalid path: "~path);
            }
            std.file.write(path, data);
            break;
          }
          case "load": {
            if(args.length > 2) throw new BrainfuckException("Too many arguments supplied to load");
            string path = root~"\\"~args[1];
            if(!std.file.exists(path)) throw new BrainfuckException("File "~path~" doesn't exist");
            if(!std.file.isFile(path)) throw new BrainfuckException(path~" isn't a file!");
            ubyte[] data = cast(ubyte[])std.file.read(path);
            int length = cast(int)(data.length/4);
            tape = [];
            for(int j = 0; j < length; j++) {
              ubyte[] tmp = data[j*4..(j+1)*4];
              int cell = tmp[0] | (tmp[1] << 0x8) | (tmp[2] << 0x10) | (tmp[3] << 0x15);
              tape ~= cell;
            }
            head = 0;
            break;
          }
          default:
            throw new BrainfuckException("Invalid directive: "~value);
        }
        break;
      }
      case TOKENS.EOF:
        break;
    }
  }
  return stdout;
}

class BrainfuckException : Exception {
  this(string msg) {
    super(msg);
  }
}