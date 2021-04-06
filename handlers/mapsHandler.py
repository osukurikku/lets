import tornado.gen
import tornado.web

from common.log import logUtils as log
from common.web import requestsManager
from constants import exceptions
from objects import beatmap
from objects import glob
from common.sentry import sentry
import requests
import os


MODULE_NAME = "maps"


class handler(requestsManager.asyncRequestHandler):
    @tornado.web.asynchronous
    @tornado.gen.engine
    @sentry.captureTornado
    def asyncGet(self, fileName=None):
        try:
            # Check arguments
            if fileName is None:
                raise exceptions.invalidArgumentsException(MODULE_NAME)
            if fileName == "":
                raise exceptions.invalidArgumentsException(MODULE_NAME)

            fileNameShort = fileName[:32] + \
                "..." if len(fileName) > 32 else fileName[:-4]
            log.info("Requested .osu file {}".format(fileNameShort))

            # Get .osu file from osu! server
            searchingBeatmap = beatmap.beatmap()
            searchingBeatmap.setData(None, None, fileName)

            if not searchingBeatmap.fileMD5:
                self.set_status(404)
                return self.write(b"")

            req = requests.get(
                f'{glob.conf.config["osuapi"]["apiurl"]}/osu/{searchingBeatmap.beatmapID}', timeout=20)
            req.encoding = "utf-8"
            response = req.content
            self.write(response)
            glob.dog.increment(glob.DATADOG_PREFIX +
                               ".osu_api.osu_file_requests")
        except exceptions.invalidArgumentsException:
            self.set_status(500)
        except exceptions.osuApiFailException:
            self.set_status(500)
