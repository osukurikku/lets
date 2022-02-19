import tornado.gen
import tornado.web

from common.web import requestsManager


class handler(requestsManager.asyncRequestHandler):
    @tornado.web.asynchronous
    @tornado.gen.engine
    def asyncGet(self):
        print("404: {}".format(self.request.uri))
        self.write(
            """
				<html>
					<head>
						<meta http-equiv="refresh" content="1;URL=https://kurikku.pw" />
					</head>
				</html>
				"""
        )
