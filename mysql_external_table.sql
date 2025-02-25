CREATE EXTERNAL TABLE mysql_products 
SETTINGS type = 'mysql', address = '127.0.0.1:3306', user = 'root', password = '123456', database = 'mysql', table = 'products';