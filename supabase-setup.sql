-- ============================================================
-- TradePro Supabase 数据库建表脚本
-- 在 Supabase SQL Editor 中一次性执行
-- ============================================================

-- 1. 业务员资料表（扩展 Supabase Auth）
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 新用户注册时自动创建 profile
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'display_name', NEW.email));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- 2. 产品库（全员共享，任何人可读写）
CREATE TABLE products (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  spec TEXT NOT NULL,
  price DECIMAL(10,2) NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  updated_by UUID REFERENCES auth.users(id)
);

ALTER TABLE products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "所有人可读产品" ON products FOR SELECT USING (true);
CREATE POLICY "登录用户可新增产品" ON products FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "登录用户可更新产品" ON products FOR UPDATE USING (auth.role() = 'authenticated');
CREATE POLICY "登录用户可删除产品" ON products FOR DELETE USING (auth.role() = 'authenticated');

-- 3. 货代运价库（全员共享）
CREATE TABLE freight (
  id BIGSERIAL PRIMARY KEY,
  countries TEXT NOT NULL,
  countries_cn TEXT DEFAULT '',
  forwarder TEXT NOT NULL,
  channel TEXT DEFAULT '',
  first_weight TEXT DEFAULT '0',
  additional_weight TEXT DEFAULT '0',
  lead_time TEXT DEFAULT '',
  note TEXT DEFAULT '',
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  updated_by UUID REFERENCES auth.users(id)
);

ALTER TABLE freight ENABLE ROW LEVEL SECURITY;
CREATE POLICY "所有人可读货代" ON freight FOR SELECT USING (true);
CREATE POLICY "登录用户可管理货代" ON freight FOR ALL USING (auth.role() = 'authenticated');

-- 4. 客户库（按用户隔离）
CREATE TABLE customers (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  contact TEXT DEFAULT '',
  phone TEXT DEFAULT '',
  email TEXT DEFAULT '',
  address TEXT DEFAULT '',
  postal TEXT DEFAULT '',
  city TEXT DEFAULT '',
  state TEXT DEFAULT '',
  country TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "用户只能看自己的客户" ON customers FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "用户可新增自己的客户" ON customers FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "用户可更新自己的客户" ON customers FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "用户可删除自己的客户" ON customers FOR DELETE USING (auth.uid() = user_id);

-- 5. 订单表（按用户隔离）
CREATE TABLE orders (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  customer_id BIGINT REFERENCES customers(id) ON DELETE SET NULL,
  customer_name TEXT DEFAULT '',
  customer_country TEXT DEFAULT '',
  subtotal DECIMAL(12,2) DEFAULT 0,
  discount_pct DECIMAL(5,2) DEFAULT 0,
  final_total DECIMAL(12,2) DEFAULT 0,
  freight_info JSONB DEFAULT '{}',
  freight_manual TEXT DEFAULT '',
  order_note TEXT DEFAULT '',
  shipping_note TEXT DEFAULT '',
  sales_person TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "用户只能看自己的订单" ON orders FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "用户可新增订单" ON orders FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "用户可更新自己的订单" ON orders FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "用户可删除自己的订单" ON orders FOR DELETE USING (auth.uid() = user_id);

-- 6. 订单明细表
CREATE TABLE order_items (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  code TEXT DEFAULT '',
  name TEXT DEFAULT '',
  spec TEXT DEFAULT '',
  qty INTEGER DEFAULT 1,
  unit_price DECIMAL(10,2) DEFAULT 0,
  line_total DECIMAL(12,2) DEFAULT 0
);

ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "用户可管理自己订单的明细"
  ON order_items FOR ALL
  USING (EXISTS (
    SELECT 1 FROM orders WHERE orders.id = order_items.order_id AND orders.user_id = auth.uid()
  ));

-- 7. 创建索引加速查询
CREATE INDEX idx_customers_user ON customers(user_id);
CREATE INDEX idx_orders_user ON orders(user_id);
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_created ON orders(created_at DESC);
CREATE INDEX idx_order_items_order ON order_items(order_id);

-- 8. 插入默认产品数据
INSERT INTO products (code, name, spec, price) VALUES
('KPV5','KPV','5mg*10vials',50),('KPV10','KPV','10mg*10vials',80),
('CND5','CJC-1295 without DAC','5mg*10vials',80),('CND10','CJC-1295 without DAC','10mg*10vials',130),
('CD5','CJC-1295 with DAC','5mg*10vials',160),('CP10','CJC-1295+Ipamorelin','10mg*10vials',110),
('IP5','Ipamorelin','5mg*10vials',50),('IP10','Ipamorelin','10mg*10vials',80),
('SMO5','Sermorelin Acetate','5mg*10vials',100),('SMO10','Sermorelin Acetate','10mg*10vials',130),
('TSM5','Tesamorelin','5mg*10vials',120),('TSM10','Tesamorelin','10mg*10vials',200),
('TSM20','Tesamorelin','20mg*10vials',350),('ET10','Epithalon','10mg*10vials',60),
('ET50','Epithalon','50mg*10vials',145),('NJ100','NAD+','100mg*10vials',60),
('NJ500','NAD+','500mg*10vials',85),('NJ1000','NAD+','1000mg*10vials',140),
('MS10','MOTS-c','10mg*10vials',80),('MS40','MOTS-c','40mg*10vials',200),
('2S10','SS-31','10mg*10vials',100),('TA5','Thymosin Alpha-1','5mg*10vials',100),
('TA10','Thymosin Alpha-1','10mg*10vials',160),('SK5','Selank','5mg*10vials',50),
('SK10','Selank','10mg*10vials',70),('XA5','Semax','5mg*10vials',50),
('XA10','Semax','10mg*10vials',60),('DS5','DSIP','5mg*10vials',55),
('DR5','Dermorphin','5mg*10vials',65),('MT1','Melanotan 1','10mg*10vials',55),
('ML10','Melanotan 2','10mg*10vials',60),('P41','PT-141','10mg*10vials',70),
('KS5','Kisspeptin-10','5mg*10vials',65),('KS10','Kisspeptin-10','10mg*10vials',100),
('GND5','Gonadorelin Acetate','5mg*10vials',75),('GND10','Gonadorelin Acetate','10mg*10vials',125),
('TR12','Triptorelin Acetate','2mg*10vials',50),('VIP5','VIP','5mg*10vials',85),
('VIP10','VIP','10mg*10vials',145),('5AM','5-Amino-1MQ','5mg*10vials',55),
('G65','GHRP-6','5mg*10vials',50),('375','LL-37','5mg*10vials',95),
('IG1','IGF-1 LR3','1mg*10vials',200),('OT5','Oxytocin Acetate','5mg*10vials',60),
('GTT600','Glutathione','600mg*10vials',50),('GTT1000','Glutathione','1500mg*10vials',80),
('BAC3','Bacteriostatic Water','3ml*10vials',10),('BAC10','Bacteriostatic Water','10ml*10vials',15),
('TR5','Tirzepatide','5mg*10vials',50),('TR10','Tirzepatide','10mg*10vials',60),
('TR15','Tirzepatide','15mg*10vials',75),('TR20','Tirzepatide','20mg*10vials',90),
('TR30','Tirzepatide','30mg*10vials',120),('TR60','Tirzepatide','60mg*10vials',195),
('TR100','Tirzepatide','100mg*10vials',295),('RT5','Retatrutide','5mg*10vials',65),
('RT10','Retatrutide','10mg*10vials',100),('RT15','Retatrutide','15mg*10vials',135),
('RT20','Retatrutide','20mg*10vials',165),('RT30','Retatrutide','30mg*10vials',215),
('RT60','Retatrutide','60mg*10vials',380),('RT100','Retatrutide','100mg*10vials',535),
('SM5','Semaglutide','5mg*10vials',50),('SM10','Semaglutide','10mg*10vials',65),
('SM20','Semaglutide','20mg*10vials',90),('SM30','Semaglutide','30mg*10vials',130),
('CGL5','Cagrilintide','5mg*10vials',135),('CGL10','Cagrilintide','10mg*10vials',210),
('5AD','AOD9604','5mg*10vials',115),('10AD','AOD9604','10mg*10vials',190),
('BC5','BPC-157','5mg*10vials',55),('BC10','BPC-157','10mg*10vials',80),
('BT5','TB-500','5mg*10vials',90),('BT10','TB-500','10mg*10vials',150),
('BB10','BPC-157+TB-500','10mg*10vials',110),('BB20','BPC-157+TB-500','20mg*10vials',200),
('CU50','GHK-Cu','50mg*10vials',40),('CU100','GHK-Cu','100mg*10vials',60),
('BBG50','Compound Peptide','50mg*10vials',155),('BBG70','Compound Peptide','70mg*10vials',200),
('KLOW','KLOW Complex Peptide','80mg*10vials',235)
ON CONFLICT (code) DO NOTHING;

-- 9. 插入默认货代数据
INSERT INTO freight (countries, countries_cn, forwarder, channel, first_weight, additional_weight, lead_time, note) VALUES
('America','美国','陈秋生','联邦快递','80','5','6-8 个工作日','不含税'),
('European Countries','欧洲各国','熊静','UPS/敦豪','80','5','6-11 个工作日','不含税'),
('United Kingdom','英国','熊静','皇家邮政','0','0','7-12 个工作日',''),
('Canada','加拿大','熊静','加拿大邮政','0','0','7-12 个工作日',''),
('Australia','澳大利亚','熊静','澳大利亚邮政','85','5','6-10 个工作日',''),
('Brazil','巴西','陈秋生','联邦快递','100','5','6-9 个工作日','买家承担关税'),
('India,UAE,Israel,Saudi Arabia,South Africa','印度,阿联酋,以色列,沙特阿拉伯,南非','熊静','UPS','100','4-5','6-9 个工作日','买家承担关税'),
('Turkey,Qatar,Mexico,Chile','土耳其,卡塔尔,墨西哥,智利','英海','','100','5','10-18 个工作日','提醒清关风险');
