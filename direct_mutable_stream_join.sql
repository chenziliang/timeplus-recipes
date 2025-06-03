-- Direct join rhs mutable stream without building hash table

CREATE MUTABLE STREAM products(id string, name string) PRIMARY KEY product_id;

SELECT * FROM orders join table(products) ON orders.product_id = products.id SETTINGS join_algorithm='direct'; 