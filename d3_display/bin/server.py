from multiprocessing import Process
from webbrowser import open_new_tab

from json_app import make_json_app
from d3_display.d3_display import d3_display


def get_app(series, axis=None):
    if axis is None:
        axis = {'x': {'label': 'x axis', 'tick_format': ',r'},
                'y': {'label': 'y axis', 'tick_format': ',r'}}

    app = make_json_app(__name__,
                        static_folder='../static',
                        template_folder='../templates',
                        )
    app.data = {'series': series, 'axis': axis}
    app.register_blueprint(d3_display)
    return app


def main():
    series = [{
        'values': [{'x': i, 'y': i} for i in range(10)],
        'key': 'Some Line',
        'color': '#ff7f0e'
    }, {
        'values': [{'x': i, 'y': 9 - i} for i in range(10)],
        'key': 'Some Other Line',
        'color': '#2ca02c'
    }]
    app = get_app(series)
    p = Process(target=app.run)
    try:
        p.start()
        open_new_tab('http://localhost:5000/hello/')
        p.join()
    except KeyboardInterrupt:
        p.terminate()


if __name__ == "__main__":
    main()
