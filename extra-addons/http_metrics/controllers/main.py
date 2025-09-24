
from odoo import http
from odoo.http import Response

class MetricsController(http.Controller):

    @http.route('/metrics', auth='none', type='http')
    def metrics(self, **kwargs):
        
        return Response("odoo_custom_metric_total 1\n", content_type='text/plain')
