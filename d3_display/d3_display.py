from flask import render_template, jsonify, Blueprint, current_app

d3_display = Blueprint('d3_display', __name__)

@d3_display.route("/hello/")
@d3_display.route("/hello/<name>")
def hello(name=None):
    return render_template('index.html', data=current_app.data)


@d3_display.route("/test/")
@d3_display.route("/test/<name>")
def test(name='world'):
    response = jsonify(hello=name)
    response.status_code = 200
    return response
