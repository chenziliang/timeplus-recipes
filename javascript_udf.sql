--

CREATE OR REPLACE FUNCTION nullable_add(i nullable(int), j nullable(int)) RETURNS nullable(int) LANGUAGE JAVASCRIPT AS $$
    function nullable_add(args_i, args_j) {

        /// console.log(args_i);
        /// console.log(args_j);

        let results = [];

        for(let idx = 0; idx < args_i.length; idx++) {
            if (args_i[idx] == null && args_j[idx] == null)
                results.push(null);
            else if (args_i[idx] == null)
                results.push(args_j[idx]);
            else if (args_j[idx] == null)
                results.push(args_j[idx]);
            else
                results.push(args_i[idx] + args_j[idx]);
        }

        /// console.log(results);
        return results;
    }
$$
