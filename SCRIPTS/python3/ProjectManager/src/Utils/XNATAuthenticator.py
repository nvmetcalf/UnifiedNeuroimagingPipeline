import requests
import time
import threading
import getpass
from bson.objectid import ObjectId
import src.Utils.DatabaseManager as DBM

class XNATAuthenticator(DBM.DatabaseManager):
    def __init__(self, database_name: str, server: str) -> None:

        super().__init__(database_name)

        #Check that the server looks valid.
        if not ('https://' in server and server[-1] == '/'):
            print(f'The server {server} is not formatted correctly.')
            raise ValueError
            
        self._server = server
        
        self.__heart_beat = None
        self._logged_in = False

        self._cookie = None
        self._mutex = threading.Lock()
    
    #This function gets a download cookie that allows http requests to authenticate correctly on CNDA.
    #lasts 15 minutes.
    def __get_session_cookie(self) -> requests.cookies.RequestsCookieJar | None:
        http_position = self._server.find('https://') + 8
        url = f'https://{self._user}:{self.__pass}@{self._server[http_position:]}data/JSESSION'
        print(f'Acquiring new cookie for {self._server}...')
        cookie_response = requests.get(url)

        if not cookie_response.ok:
            self._mutex.acquire()
            print(f'Authentication failed for user {self._user} on server {self._server}.')
            self._mutex.release()
            self._logged_in = False
            return None

        #Otherwise return the cookejar
        return cookie_response.cookies
    
    #Keeps the current connection alive by requesting a new log in cookie every time interval.
    #Requires the number of minutes to send a refresh response.
    def __keep_connection_alive(self, refresh_rate :int):
        keep_alive_time = refresh_rate * 60 #Every 10 minutes get a new cookie from xnat to keep the session alive.
        def get_login_cookie():
            start_time = time.perf_counter()
            while True:
                #Check if the user is still logged in.
                self._mutex.acquire()
                if not self._logged_in:
                    self._mutex.release()
                    break
                
                self._mutex.release()

                #Check how much time has elapsed
                current_time = time.perf_counter()
                if current_time - start_time >= keep_alive_time:
                    start_time = current_time 
                    
                    self._mutex.acquire()
                    self._cookie = self.__get_session_cookie()
                    if self._cookie == '':
                        print(f'Could not refresh login cookie for user, logging out...')
                        self._logged_in = False
                        self._mutex.release()
                        break

                    self._mutex.release()

                time.sleep(1)

        self.__heart_beat = threading.Thread(target=get_login_cookie)
        self.__heart_beat.start()
    
    def login(self, user_name: str) -> bool:
        self._user = user_name
        self.__pass = getpass.getpass(f'Please enter your password for the xnat server {self._server}: ')

        self._cookie = self.__get_session_cookie() 
        if self._cookie:
            self._logged_in = True
            self.__keep_connection_alive(refresh_rate = 10)

        return self._logged_in

    def logout(self) -> None:
        if self._logged_in:
            self._mutex.acquire()
            self._logged_in = False
            self._mutex.release()
            self.__heart_beat.join()
