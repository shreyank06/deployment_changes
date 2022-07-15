import pprint
import json
from jinja2 import Environment, FileSystemLoader
import os
import sys

def parse_other(file_to_parse, dictionary_keys, array_rc):

        with open(file_to_parse) as f:

                for line in f:
                
                #condition to ignore any lines not starting from r or c

                        if((line[0] == 'r') or (line[0] == 'c')):

                                line = line.split()
                                dictionary_keys.append(line[1])
                                dictionary_keys = list(dict.fromkeys(dictionary_keys))
                                components = dict.fromkeys(dictionary_keys)
                                array_rc.append(line)

        return components,dictionary_keys,array_rc


def manipulate_r(r: list) -> list:

        routes = ['ip', 'r', 'a']

        routes.append(r[2])
        routes.append('via')
        routes.append(r[3])

        return routes

def manipulate_c(c: list) -> list:

        del c[0]
        del c[0]

        #for deleting comments on any commands
        if('#' in c):
                        
               get_index = c.index('#')
                
               del(c[get_index:len(c)])

        return c

def create_dictionary(components, dictionary_keys, array_rc) -> dict:

        for key in dictionary_keys:

                commands_for_specific_keys = []

                for commands in array_rc:

                        if(key in commands):

                                if(commands[0] == 'r'):

                                        new_command = manipulate_r(commands)
                                else:
                                        new_command = manipulate_c(commands)
                                        
                                        if('-I' in ' '.join(new_command)):

                                                iptable_command = ' '.join(commands).replace("-I", "-D")
                                                commands_for_specific_keys.append(iptable_command)

                                        elif('-A' in ' '.join(new_command)):

                                                iptable_command = ' '.join(commands).replace("-A", "-D")
                                                commands_for_specific_keys.append(iptable_command)

                                commands_for_specific_keys.append(' '.join(new_command))

                #for adding common config call for uexxx
                if(key.startswith('ue')):
                        commands_for_specific_keys = []  #as all commands for ue are placed in ue_common_config
                        commands_for_specific_keys.append("ue_common_configuration")

                #  #for adding common config call for gnbxxx, commented as common config call for gnb is not needed
                # elif(key.startswith('gnb')):
                #         commands_for_specific_keys.append("gnb_common_configuration")

                 #for adding common config call for igw and dnxxx
                elif(key.startswith('igw') or key.startswith('dn')):

                        commands_for_specific_keys.append("dn_common_configuration")

                        #for deleting iptable command with MASQUERADE in it
                        stringlist = [commands for commands in commands_for_specific_keys if not "MASQUERADE" in commands]
                        commands_for_specific_keys = stringlist

                        #for deleting default route 
                        stringlist = [commands for commands in commands_for_specific_keys if not "ip r a default" in commands]
                        commands_for_specific_keys = stringlist

                #adding final commands for each components
                components[key] = commands_for_specific_keys

                #deleting prometheus object
                if('prometheus' in components):
                        del components["prometheus"]
                        
        return components


def render_template():

  file_loader = FileSystemLoader("template")
  env = Environment(loader=file_loader)
  template = env.get_template("run_service.j2")
  env.trim_blocks = True
  env.lstrip_blocks = True

  return(template.render(parsed_json_object = parsed_file))


def write_file(output, path):
  with open(path, 'w') as f:
    f.write(output)
  print(f"Created file {path}")


if __name__ == "__main__":

        dictionary_keys = []

        array_rc = []

        if('other' in sys.argv or 'other2' in sys.argv):

            components,dictionary_keys,array_rc = parse_other(sys.argv[1], dictionary_keys, array_rc)

            parsed_file = create_dictionary(components, dictionary_keys, array_rc)

            parsed_json_object = json.dumps(parsed_file, indent = 4)

            path = 'run_service.sh'
            redered = render_template()
            write_file(redered, path)
            os.chmod(path, 0o755)

        else:

            print("Expected other or other2 as an argument")

        




