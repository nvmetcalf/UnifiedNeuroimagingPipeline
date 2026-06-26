import builtins
import tqdm

class Logger(object):

    def __init__(self, logging_path = '', print_to_consol = True) -> None:
        self._log_file = None
        
        #Set up print.
        self.__default_print = builtins.print
        self.__print = self.__default_print
        
        self.__print_to_consol = print_to_consol

        if logging_path != None and logging_path != '':
            self._log_file = open(logging_path, 'w')
            self._log_path = logging_path
    
    #These are used for context management. This is to get the logger to work.
    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> None:
        if not self._log_file == None:
            self._log_file.close()

    def set_tqdm_print(self) -> None:
        self.__print = lambda *args, **kwargs: tqdm.tqdm.write(" ".join(map(str, args)))

    def unset_tqdm_print(self) -> None:
        self.__print == self.__default_print
    
    def log(self, message: str) -> None:

        if self.__print_to_consol:
            self.__print(message)

        if self._log_file != None: 
            self._log_file.write(message + '\n')
