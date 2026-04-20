-- Seed product catalog. Re-runnable via ON CONFLICT DO NOTHING.

INSERT INTO products (sku, title, description, price_cents, image_url, stock) VALUES
    ('NETLIX-TEE-BLK-M',  'Netlix Logo Tee — Black (M)',  'Soft cotton tee with embroidered Netlix mark.',           2499, '/img/tee-black.png',   120),
    ('NETLIX-HOOD-NVY-L', 'Netlix Hoodie — Navy (L)',     'Heavyweight pullover hoodie in deep navy.',              5999, '/img/hoodie-navy.png',  60),
    ('NETLIX-CAP-WHT',    'Netlix Dad Cap — White',       'Unstructured 6-panel cap with low-profile mark.',        1899, '/img/cap-white.png',    80),
    ('NETLIX-MUG-CER',    'Netlix Ceramic Mug',           '12oz ceramic mug. Dishwasher safe.',                     1299, '/img/mug.png',         200),
    ('NETLIX-STICK-PACK', 'Netlix Sticker Pack',          'Five vinyl stickers in assorted Netlix marks.',           599, '/img/stickers.png',    500),
    ('NETLIX-SOCK-CRW',   'Netlix Crew Socks',            'Combed cotton crew socks. One size.',                     899, '/img/socks.png',       150)
ON CONFLICT (sku) DO NOTHING;
