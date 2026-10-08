-- db/profiles/steel/seed.sql — the STEEL PROCESSING profile (docs/processcore-design.md §4, D12): a steel service
-- center that buys master coils by heat with mill test reports and slits, cuts to length, shears, blanks and levels
-- them into slit coils, sheets and blanks, packs them on skids and ships them by truck; scrap sold by weight.
-- Applied once by deploy/os-provision.sh (recorded as profile:steel in app.schema_migrations) or by
-- deploy/provision-client.sh, as processcore_app. Idempotent. Industry is data, not code: nothing in PHP says "coil".
SET search_path = app, public;

-- Display units and the profile's name --------------------------------------------------------------------------
UPDATE app.client_settings SET profile = 'steel', mass_display_unit = 'lb', length_display_unit = 'in', area_display_unit = 'ft2' WHERE id = 1;

-- Number formats for the steel classes ----------------------------------------------------------------------------
INSERT INTO app.number_sequences (key, format, period_reset) VALUES
    ('coil',  'C-{YY}-{N:5}', 'year'),
    ('sheet', 'S-{YY}-{N:5}', 'year'),
    ('skid',  'K-{YY}-{N:5}', 'year'),
    ('scrap', 'X-{YY}-{N:5}', 'year')
ON CONFLICT (key) DO NOTHING;

-- Item classes (steel density 7,850 kg/m³ for theoretical weight) ----------------------------------------------
INSERT INTO app.item_classes (code, name, kind, purchasable, process_input, catch_weight, serialized, lot_noun, lot_noun_plural, lot_number_key, density_kg_m3, display_order) VALUES
    ('coil',      'Coil',       'material', true,  true,  true,  true,  'Coil',  'Coils',  'coil',  7850, 11),
    ('slit_coil', 'Slit coil',  'material', false, true,  true,  true,  'Coil',  'Coils',  'coil',  7850, 12),
    ('sheet',     'Sheet',      'material', true,  true,  false, false, 'Lot',   'Lots',   'sheet', 7850, 13),
    ('blank',     'Blank',      'material', false, true,  false, false, 'Lot',   'Lots',   'sheet', 7850, 14),
    ('scrap',     'Scrap',      'material', false, false, true,  false, 'Scrap lot', 'Scrap lots', 'scrap', 7850, 51)
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, lot_noun = EXCLUDED.lot_noun, lot_noun_plural = EXCLUDED.lot_noun_plural,
                                 lot_number_key = EXCLUDED.lot_number_key, density_kg_m3 = EXCLUDED.density_kg_m3;
UPDATE app.item_classes SET lot_noun = 'Skid', lot_noun_plural = 'Skids', lot_number_key = 'skid', density_kg_m3 = 7850 WHERE code = 'finished_good';
UPDATE app.item_classes SET density_kg_m3 = 7850 WHERE code IN ('material','intermediate','co_product');

-- The attribute dictionary ---------------------------------------------------------------------------------------
INSERT INTO app.attribute_definitions (key, name, kind, unit_code, decimals, choices, on_items, on_products, on_lots, inherit, in_code, display_order) VALUES
    ('grade',           'Grade',               'text',   NULL,  0, NULL, true,  true,  true,  true,  true,  10),
    ('spec',            'Specification',       'text',   NULL,  0, NULL, true,  true,  true,  true,  false, 11),
    ('thickness_in',    'Thickness',           'num',    'in',  4, NULL, true,  true,  true,  true,  true,  20),
    ('gauge',           'Gauge',               'text',   NULL,  0, NULL, true,  true,  false, false, false, 21),
    ('width_in',        'Width',               'num',    'in',  3, NULL, true,  true,  true,  false, true,  30),
    ('length_in',       'Length',              'num',    'in',  3, NULL, true,  true,  true,  false, true,  40),
    ('coating',         'Coating',             'choice', NULL,  0, '{none,G30,G40,G60,G90,A25,A40,galvannealed,electrogalvanized,other}', true, true, true, true, true, 50),
    ('finish',          'Surface finish',      'choice', NULL,  0, '{hot_rolled,pickled_oiled,cold_rolled,galvanized,galvannealed,aluminized,stainless_2b,stainless_4,other}', true, true, true, true, false, 51),
    ('heat',            'Heat number',         'text',   NULL,  0, NULL, false, false, true,  true,  false, 60),
    ('mill',            'Mill',                'text',   NULL,  0, NULL, false, false, true,  true,  false, 61),
    ('country_of_melt', 'Country of melt',     'text',   NULL,  0, NULL, false, false, true,  true,  false, 62),
    ('mtr_no',          'MTR number',          'text',   NULL,  0, NULL, false, false, true,  true,  false, 63),
    ('piw',             'PIW (lb per inch of width)', 'num', 'lb', 1, NULL, false, false, true, false, false, 70),
    ('yield_ksi',       'Yield strength',      'num',    NULL,  1, NULL, false, false, true,  true,  false, 80),
    ('tensile_ksi',     'Tensile strength',    'num',    NULL,  1, NULL, false, false, true,  true,  false, 81),
    ('elongation_pct',  'Elongation',          'num',    NULL,  1, NULL, false, false, true,  true,  false, 82),
    ('hardness_hrb',    'Hardness (HRB)',      'num',    NULL,  1, NULL, false, false, true,  true,  false, 83),
    ('chem_c',          'Carbon (%)',          'num',    NULL,  3, NULL, false, false, true,  true,  false, 90),
    ('chem_mn',         'Manganese (%)',       'num',    NULL,  3, NULL, false, false, true,  true,  false, 91),
    ('chem_p',          'Phosphorus (%)',      'num',    NULL,  3, NULL, false, false, true,  true,  false, 92),
    ('chem_s',          'Sulfur (%)',          'num',    NULL,  3, NULL, false, false, true,  true,  false, 93),
    ('chem_si',         'Silicon (%)',         'num',    NULL,  3, NULL, false, false, true,  true,  false, 94),
    ('edge',            'Edge condition',      'choice', NULL,  0, '{mill,slit,sheared,deburred}', false, true, true, false, false, 100),
    ('pieces_per_package', 'Pieces per package', 'num',  'ea',  0, NULL, true,  false, false, false, false, 110)
ON CONFLICT (key) DO UPDATE SET name = EXCLUDED.name, kind = EXCLUDED.kind, unit_code = EXCLUDED.unit_code, decimals = EXCLUDED.decimals,
                                choices = EXCLUDED.choices, on_items = EXCLUDED.on_items, on_products = EXCLUDED.on_products, on_lots = EXCLUDED.on_lots,
                                inherit = EXCLUDED.inherit, in_code = EXCLUDED.in_code, display_order = EXCLUDED.display_order;

INSERT INTO app.item_class_attributes (item_class, attribute_key, required, display_order) VALUES
    ('coil', 'grade', true, 10), ('coil', 'spec', false, 11), ('coil', 'thickness_in', true, 20), ('coil', 'gauge', false, 21),
    ('coil', 'width_in', true, 30), ('coil', 'coating', false, 50), ('coil', 'finish', false, 51),
    ('slit_coil', 'grade', true, 10), ('slit_coil', 'spec', false, 11), ('slit_coil', 'thickness_in', true, 20), ('slit_coil', 'gauge', false, 21),
    ('slit_coil', 'width_in', true, 30), ('slit_coil', 'coating', false, 50), ('slit_coil', 'finish', false, 51),
    ('sheet', 'grade', true, 10), ('sheet', 'spec', false, 11), ('sheet', 'thickness_in', true, 20), ('sheet', 'gauge', false, 21),
    ('sheet', 'width_in', true, 30), ('sheet', 'length_in', true, 40), ('sheet', 'coating', false, 50), ('sheet', 'finish', false, 51),
    ('blank', 'grade', true, 10), ('blank', 'thickness_in', true, 20), ('blank', 'width_in', true, 30), ('blank', 'length_in', true, 40), ('blank', 'coating', false, 50),
    ('finished_good', 'grade', false, 10), ('finished_good', 'thickness_in', false, 20), ('finished_good', 'width_in', false, 30),
    ('finished_good', 'length_in', false, 40), ('finished_good', 'pieces_per_package', false, 110),
    ('scrap', 'grade', false, 10), ('scrap', 'coating', false, 50)
ON CONFLICT DO NOTHING;

-- Operations --------------------------------------------------------------------------------------------------------
INSERT INTO app.operations (code, name, kind, description, display_order, is_terminal) VALUES
    ('slit',          'Slit',          'convert', 'One coil into narrower coils (the mults) plus edge trim scrap',   10, false),
    ('cut_to_length', 'Cut to length', 'convert', 'A coil into sheets of a length, stacked; head and tail scrap',    20, false),
    ('shear',         'Shear',         'convert', 'Sheets into smaller sheets',                                       30, false),
    ('blank',         'Blank',         'convert', 'Sheets or coil into blanks on a press',                            40, false),
    ('level',         'Level',         'convert', 'Flatten; usually a step on the cut-to-length line',                50, false),
    ('pack',          'Pack',          'pack',    'Onto skids with banding and paper',                                80, true),
    ('inspect',       'Inspect',       'inspect', 'Dimensional and surface inspection',                               90, false)
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, kind = EXCLUDED.kind, description = EXCLUDED.description, display_order = EXCLUDED.display_order;

-- Measurement types -------------------------------------------------------------------------------------------------
INSERT INTO app.measurement_types (code, name, unit, decimals, min_valid, max_valid, display_order) VALUES
    ('thickness_in',    'Thickness',         'in',      4, 0,    3,    10),
    ('width_in',        'Width',             'in',      3, 0,    120,  20),
    ('length_in',       'Length',            'in',      3, 0,    1200, 30),
    ('flatness_iunit',  'Flatness',          'I-unit',  1, 0,    200,  40),
    ('camber_in_ft',    'Camber',            'in/ft',   4, 0,    1,    41),
    ('crown_in',        'Crown',             'in',      4, 0,    0.1,  42),
    ('squareness_in',   'Squareness',        'in',      3, 0,    2,    43),
    ('burr_in',         'Burr height',       'in',      4, 0,    0.1,  44),
    ('hardness_hrb',    'Hardness',          'HRB',     1, 0,    120,  50),
    ('yield_ksi',       'Yield strength',    'ksi',     1, 0,    200,  51),
    ('tensile_ksi',     'Tensile strength',  'ksi',     1, 0,    250,  52),
    ('elongation_pct',  'Elongation',        '%',       1, 0,    80,   53),
    ('coating_oz_ft2',  'Coating weight',    'oz/ft²',  2, 0,    3,    60),
    ('weight_lb',       'Weight',            'lb',      0, 0,    100000, 70)
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, unit = EXCLUDED.unit, decimals = EXCLUDED.decimals, min_valid = EXCLUDED.min_valid, max_valid = EXCLUDED.max_valid;

-- Equipment kinds ---------------------------------------------------------------------------------------------------
INSERT INTO app.equipment_kinds (code, name, display_order) VALUES
    ('slitter',            'Slitter',            10),
    ('cut_to_length_line', 'Cut-to-length line', 20),
    ('shear',              'Shear',              30),
    ('leveler',            'Leveler',            40),
    ('blanking_press',     'Blanking press',     50),
    ('laser',              'Laser',              60),
    ('plasma',             'Plasma table',       61),
    ('saw',                'Saw',                62)
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, display_order = EXCLUDED.display_order;

-- Reason codes ------------------------------------------------------------------------------------------------------
INSERT INTO app.reason_codes (code, name, applies_to, report_category, classification) VALUES
    ('TRIM',     'Edge trim',                    'scrap',      'scrap',            'expected'),
    ('ENDS',     'Head and tail',                'scrap',      'scrap',            'expected'),
    ('SETUP',    'Setup scrap',                  'scrap',      'scrap',            'expected'),
    ('OFFGAUGE', 'Off gauge',                    'scrap',      'exceptional_loss', 'exceptional'),
    ('SURFACE',  'Surface defect',               'scrap',      'exceptional_loss', 'exceptional'),
    ('CAMBER',   'Camber or flatness out of spec','scrap',     'exceptional_loss', 'exceptional'),
    ('RUST',     'Rust or storage damage',       'adjustment', 'damage',           'exceptional')
ON CONFLICT (code) DO NOTHING;

-- Gauge tables: Manufacturers' Standard Gauge for sheet steel (41.82 lb/ft² per inch), and galvanized ---------------
INSERT INTO app.reference_values (table_name, key, value_num, note, sort_order) VALUES
    ('gauge_sheet_steel', '3',  0.2391, 'in', 3),  ('gauge_sheet_steel', '4',  0.2242, 'in', 4),  ('gauge_sheet_steel', '5',  0.2092, 'in', 5),
    ('gauge_sheet_steel', '6',  0.1943, 'in', 6),  ('gauge_sheet_steel', '7',  0.1793, 'in', 7),  ('gauge_sheet_steel', '8',  0.1644, 'in', 8),
    ('gauge_sheet_steel', '9',  0.1495, 'in', 9),  ('gauge_sheet_steel', '10', 0.1345, 'in', 10), ('gauge_sheet_steel', '11', 0.1196, 'in', 11),
    ('gauge_sheet_steel', '12', 0.1046, 'in', 12), ('gauge_sheet_steel', '13', 0.0897, 'in', 13), ('gauge_sheet_steel', '14', 0.0747, 'in', 14),
    ('gauge_sheet_steel', '15', 0.0673, 'in', 15), ('gauge_sheet_steel', '16', 0.0598, 'in', 16), ('gauge_sheet_steel', '17', 0.0538, 'in', 17),
    ('gauge_sheet_steel', '18', 0.0478, 'in', 18), ('gauge_sheet_steel', '19', 0.0418, 'in', 19), ('gauge_sheet_steel', '20', 0.0359, 'in', 20),
    ('gauge_sheet_steel', '21', 0.0329, 'in', 21), ('gauge_sheet_steel', '22', 0.0299, 'in', 22), ('gauge_sheet_steel', '23', 0.0269, 'in', 23),
    ('gauge_sheet_steel', '24', 0.0239, 'in', 24), ('gauge_sheet_steel', '25', 0.0209, 'in', 25), ('gauge_sheet_steel', '26', 0.0179, 'in', 26),
    ('gauge_sheet_steel', '28', 0.0149, 'in', 28), ('gauge_sheet_steel', '30', 0.0120, 'in', 30),
    ('gauge_galvanized', '8',  0.1681, 'in', 8),  ('gauge_galvanized', '9',  0.1532, 'in', 9),  ('gauge_galvanized', '10', 0.1382, 'in', 10),
    ('gauge_galvanized', '11', 0.1233, 'in', 11), ('gauge_galvanized', '12', 0.1084, 'in', 12), ('gauge_galvanized', '13', 0.0934, 'in', 13),
    ('gauge_galvanized', '14', 0.0785, 'in', 14), ('gauge_galvanized', '15', 0.0710, 'in', 15), ('gauge_galvanized', '16', 0.0635, 'in', 16),
    ('gauge_galvanized', '17', 0.0575, 'in', 17), ('gauge_galvanized', '18', 0.0516, 'in', 18), ('gauge_galvanized', '19', 0.0456, 'in', 19),
    ('gauge_galvanized', '20', 0.0396, 'in', 20), ('gauge_galvanized', '21', 0.0366, 'in', 21), ('gauge_galvanized', '22', 0.0336, 'in', 22),
    ('gauge_galvanized', '23', 0.0306, 'in', 23), ('gauge_galvanized', '24', 0.0276, 'in', 24), ('gauge_galvanized', '25', 0.0247, 'in', 25),
    ('gauge_galvanized', '26', 0.0217, 'in', 26), ('gauge_galvanized', '28', 0.0187, 'in', 28), ('gauge_galvanized', '30', 0.0157, 'in', 30),
    ('density_kg_m3', 'carbon_steel', 7850, 'kg/m³', 1), ('density_kg_m3', 'stainless_steel', 8000, 'kg/m³', 2), ('density_kg_m3', 'aluminum', 2700, 'kg/m³', 3)
ON CONFLICT (table_name, key) DO UPDATE SET value_num = EXCLUDED.value_num, note = EXCLUDED.note, sort_order = EXCLUDED.sort_order;

-- Dashboard tiles the profile asks for (the dashboard reads settings.dashboard.tiles) ------------------------------
UPDATE app.client_settings
   SET settings = settings || jsonb_build_object('dashboard', jsonb_build_object('tiles',
       jsonb_build_array('coils_in_yard', 'runs_today', 'orders_due_week', 'scrap_month', 'release_queue', 'coils_below_reorder')))
 WHERE id = 1 AND NOT (settings ? 'dashboard');
