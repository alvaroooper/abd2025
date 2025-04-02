DROP TABLE detalle_pedido CASCADE CONSTRAINTS;
DROP TABLE pedidos CASCADE CONSTRAINTS;
DROP TABLE platos CASCADE CONSTRAINTS;
DROP TABLE personal_servicio CASCADE CONSTRAINTS;
DROP TABLE clientes CASCADE CONSTRAINTS;

DROP SEQUENCE seq_pedidos;


-- Creación de tablas y secuencias

create sequence seq_pedidos;

CREATE TABLE clientes (
    id_cliente INTEGER PRIMARY KEY,
    nombre VARCHAR2(100) NOT NULL,
    apellido VARCHAR2(100) NOT NULL,
    telefono VARCHAR2(20)
);

CREATE TABLE personal_servicio (
    id_personal INTEGER PRIMARY KEY,
    nombre VARCHAR2(100) NOT NULL,
    apellido VARCHAR2(100) NOT NULL,
    pedidos_activos INTEGER DEFAULT 0 CHECK (pedidos_activos <= 5)
);

CREATE TABLE platos (
    id_plato INTEGER PRIMARY KEY,
    nombre VARCHAR2(100) NOT NULL,
    precio DECIMAL(10, 2) NOT NULL,
    disponible INTEGER DEFAULT 1 CHECK (DISPONIBLE in (0,1))
);

CREATE TABLE pedidos (
    id_pedido INTEGER PRIMARY KEY,
    id_cliente INTEGER REFERENCES clientes(id_cliente),
    id_personal INTEGER REFERENCES personal_servicio(id_personal),
    fecha_pedido DATE DEFAULT SYSDATE,
    total DECIMAL(10, 2) DEFAULT 0
);

CREATE TABLE detalle_pedido (
    id_pedido INTEGER REFERENCES pedidos(id_pedido),
    id_plato INTEGER REFERENCES platos(id_plato),
    cantidad INTEGER NOT NULL,
    PRIMARY KEY (id_pedido, id_plato)
);


	
-- Procedimiento a implementar para realizar la reserva
create or replace procedure registrar_pedido(
    arg_id_cliente      INTEGER, 
    arg_id_personal     INTEGER, 
    arg_id_primer_plato INTEGER DEFAULT NULL,
    arg_id_segundo_plato INTEGER DEFAULT NULL
) is 

    -----------------------------------------------------------
    --Declaración de excepciones
    -----------------------------------------------------------
    -- Excepción para cuando se quiere crear un pedido sin platos
    ex_pedido_sin_platos EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_pedido_sin_platos, -20002);
    msg_pedido_sin_platos CONSTANT VARCHAR2(100) := 'El pedido debe tener al menos un plato seleccionado.';
    
    -- Excepción para cuando se quiere introducir un pato no disponible
    ex_plato_no_disponible  EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_plato_no_disponible, -20001);
    msg_plato_no_disponible CONSTANT VARCHAR2(100) := 'El plato introducido no está disponible';

    -- Excepción para cuando el personal está sin capacidad
    ex_personal_sin_capacidad  EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_personal_sin_capacidad, -20003);
    msg_personal_sin_capacidad CONSTANT VARCHAR2(100) := 'El personal no tiene capacidad dsiponible';
    
    -- Excepción para cuando se quiere introducir un plato inexistente
    ex_plato_no_existe  EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_plato_no_existe, -20004);
    msg_plato_no_existe CONSTANT VARCHAR2(100) := 'El plato no nexiste';

    -- Excepción para cuando el cliente no existe
    ex_cliente_no_existe EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_cliente_no_existe, -20005); -- Siguiente código de error
    msg_cliente_no_existe CONSTANT VARCHAR2(100) := 'El cliente especificado no existe.';

    -- Excepción para personal de servicio inexistente
    ex_personal_no_existe EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_personal_no_existe, -20006);
    msg_personal_no_existe CONSTANT VARCHAR2(100) := 'El personal de servicio no existe.';

    -----------------------------------------------------------
    --Declaración de variables
    -----------------------------------------------------------
    existenciasPlato1 INTEGER;
    existenciasPlato2 INTEGER;

    disponibilidadPlato1 platos.disponible%TYPE;
    disponibilidadPlato2 platos.disponible%TYPE;
    
    cantidadPedidosActivos personal_servicio.pedidos_activos%type;
    
    precioPlato1 INTEGER;
    precioPlato2 INTEGER;
    precioTotal INTEGER;
    siguienteId INTEGER;

    v_cliente_count INTEGER;

    existe_personal INTEGER;


 begin
    -----------------------------------------------------------
    --Comprobación de que se selecciona al menos un plato
    -----------------------------------------------------------
    if arg_id_primer_plato is NULL and arg_id_segundo_plato is NULL then
        raise_application_error(-20002, msg_pedido_sin_platos);
    end if;
    
    -----------------------------------------------------------
    -- Validación del primer plato (existencia y disponibilidad)
    -----------------------------------------------------------
    if arg_id_primer_plato is not null then
        -- Controlar excepción plato inexistente
        select count(*) into existenciasPlato1 from platos
        where id_plato = arg_id_primer_plato;
        if existenciasPlato1 = 0 then 
            raise_application_error(-20004, msg_plato_no_existe);
        else
            -- Controlar excepción plato no disponible
            select disponible into disponibilidadPlato1 from platos WHERE id_plato = arg_id_primer_plato;
            if disponibilidadPlato1 = 0 then
                raise_application_error(-20001, msg_plato_no_disponible);
            end if;
        end if;
        
        SELECT precio
        INTO precioPlato1
        FROM Platos
        WHERE id_plato = arg_id_primer_plato;
    end if;
    
    
    -----------------------------------------------------------
    -- Validación del segundo plato (existencia y disponibilidad)
    -----------------------------------------------------------
    if arg_id_segundo_plato is not null then
        -- Controlar excepción plato inexistente
        select count(*) into existenciasPlato2 from platos
        where id_plato = arg_id_segundo_plato;
        if existenciasPlato2 = 0 then
            raise_application_error(-20004, msg_plato_no_existe);
        else
            -- Controlar excepción plato no disponible
            select disponible into disponibilidadPlato2 from platos WHERE id_plato = arg_id_segundo_plato;
            if disponibilidadPlato2 = 0 then
                raise_application_error(-20001, msg_plato_no_disponible);
            end if;
        end if;
        
        SELECT precio
        INTO precioPlato2
        FROM Platos
        WHERE id_plato = arg_id_segundo_plato;
    end if;

    SELECT COUNT(*)
    INTO v_cliente_count
    FROM clientes
    WHERE id_cliente = arg_id_cliente;
    
    IF v_cliente_count = 0 THEN
        raise_application_error(-20005, msg_cliente_no_existe);
    end if;

    SELECT COUNT(*) INTO existe_personal
    FROM personal_servicio
    WHERE id_personal = arg_id_personal;
    
    if existe_personal = 0 then
        raise_application_error(-20006, msg_personal_no_existe);
    end if;

    ----------------------------------------------------------------------------
    --Validación y bloqueo del personal de servicio para control de concurrencia
    ----------------------------------------------------------------------------
    -- Controlar excepción personal sin capacidad
    select pedidos_activos into cantidadPedidosActivos 
    from personal_servicio
    where id_personal = arg_id_personal
    FOR UPDATE; -- Se usa FOR UPDATE para evitar lecturas concurrentes)
    if cantidadPedidosActivos = 5 then
        raise_application_error(-20003, msg_personal_sin_capacidad);
    end if;

	
    ------------------------------------------------------------------
    --Cálculo del precio total y obtención del siguiente ID de pedido
    ------------------------------------------------------------------
    precioTotal := precioPlato1 + precioPlato2;
    siguienteId := seq_pedidos.nextval;

    -----------------------------------------------------------
    --Registro del pedido 
    -----------------------------------------------------------
    INSERT INTO pedidos (id_pedido, id_cliente, id_personal, fecha_pedido, total)
    VALUES (siguienteId, arg_id_cliente, arg_id_personal, SYSDATE, precioTotal);
    
    if arg_id_primer_plato is not null then
        INSERT INTO detalle_pedido (id_pedido, id_plato, cantidad)
        VALUES (siguienteId, arg_id_primer_plato, 1);
    end if;
    if arg_id_segundo_plato is not null then
        INSERT INTO detalle_pedido (id_pedido, id_plato, cantidad)
        VALUES (siguienteId, arg_id_segundo_plato, 1);
    end if;
    
    UPDATE personal_servicio
    SET pedidos_activos = pedidos_activos + 1
    WHERE id_personal = arg_id_personal;

EXCEPTION
    when others then
    rollback;
    raise;
    
end;
/

------ Deja aquí tus respuestas a las preguntas del enunciado:
-- NO SE CORREGIRÁN RESPUESTAS QUE NO ESTÉN AQUÍ (utiliza el espacio que necesites apra cada una)
-- * P4.1
--      Para garantizar en nuestro código que ningún miembro del personal de servicio supere
--      el límite de pedidos activos, antes de realizar el UPDATE donde le sumamos uno al
--      número de pedidos activos del personal de servicio correspondiente, nos aseguramos
--      de que antes de actualizar su número de pedidos no sea el del límite, que en este caso
--      es 5. Si el número de pedidos activos es 5, lanzaría la excepción 
--      ex_personal_sin_capacidad y no llegaría a realizar la actualización.
-- * P4.2
--      Para evitar que dos transacciones concurrentes asignen un pedido al mismo personal de 
--      servicio cuyos pedidos activos están a punto de superar el límite, lo que hacemos es
--      realizar un bloqueo pesimista, para ello realizamos un bloqueo de escritura con el 
--      FOR  UPDATE de tal forma que la primera transacción que acceda adquiere el bloqueo,
--      y la siguiente transacción si quiere escribir sobre la fila del mismo personal de servicio
--      tendrá que esperar a que la transacción que ha adquirido el bloqueo finalice y de esta forma
--      libere el bloqueo.
-- * P4.3
--      Sí, podemos asegurar en gran medida la consistencia. Usamos FOR UPDATE cuando
--      consultamos los pedidos_activos del personal. Esto bloquea la fila de ese
--      trabajador, obligando a que otras operaciones concurrentes sobre el mismo
--      trabajador esperen. De esta forma, nos aseguramos de que nuestra comprobación
--      del límite (si es 5) y la posterior actualización del contador se hagan sin
--      interferencias que puedan llevar a superar dicho límite. Además, el ROLLBACK
--      final en caso de cualquier error asegura que la operación es atómica: o
--      insertamos/actualizamos todo, o no dejamos rastro.
-- * P4.4
--      Esta pregunta ha quedado invalidada por encontrarse ya añadido el CHECK correspondiente al enunciado
--      en la tabla de personal_servicio en el atributo de pedidos_activos.
-- * P4.5
--      En nuestro caso, utilizamos una técnica de programación defensiva, lo que puede observarse en 
--      el código, debido a que antes de realizar alguna operación DML comprobamos que las características
--      del pedido son las correctas, y si no es así, se lanza la excepción correspondiente a cada problema
--      para registrar un pedido, haciendo así que salten las excepciones si existen antes de realizar las
--      operaciones.



-----------------------------------------------------------
-- Procedimiento dado para resetear la secuencia
-----------------------------------------------------------
create or replace
procedure reset_seq( p_seq_name varchar )
is
    l_val number;
begin
    execute immediate
    'select ' || p_seq_name || '.nextval from dual' INTO l_val;

    execute immediate
    'alter sequence ' || p_seq_name || ' increment by -' || l_val || 
                                                          ' minvalue 0';
    execute immediate
    'select ' || p_seq_name || '.nextval from dual' INTO l_val;

    execute immediate
    'alter sequence ' || p_seq_name || ' increment by 1 minvalue 0';

end;
/

-----------------------------------------------------------
-- Procedimiento  dado para inicializar la base de datos
-----------------------------------------------------------

create or replace procedure inicializa_test is
begin
    
    reset_seq('seq_pedidos');
        
  
    delete from Detalle_pedido;
    delete from Pedidos;
    delete from Platos;
    delete from Personal_servicio;
    delete from Clientes;
    
    -- Insertar datos de prueba
    insert into Clientes (id_cliente, nombre, apellido, telefono) values (1, 'Pepe', 'Perez', '123456789');
    insert into Clientes (id_cliente, nombre, apellido, telefono) values (2, 'Ana', 'Garcia', '987654321');
    
    insert into Personal_servicio (id_personal, nombre, apellido, pedidos_activos) values (1, 'Carlos', 'Lopez', 0);
    insert into Personal_servicio (id_personal, nombre, apellido, pedidos_activos) values (2, 'Maria', 'Fernandez', 5);
    
    insert into Platos (id_plato, nombre, precio, disponible) values (1, 'Sopa', 10.0, 1);
    insert into Platos (id_plato, nombre, precio, disponible) values (2, 'Pasta', 12.0, 1);
    insert into Platos (id_plato, nombre, precio, disponible) values (3, 'Carne', 15.0, 0);

    commit;
end;
/

exec inicializa_test;

-- Completa lost test, incluyendo al menos los del enunciado y añadiendo los que consideres necesarios

-----------------------------------------------------------------------------
-- Procedimiento para realizar los tests, comprobando que el código funcione
-----------------------------------------------------------------------------

create or replace procedure test_registrar_pedido is
begin
	 
    ---------------------------------------------------------------------
    -- Test para comprobar el caso 1 de un pedido correcto sin fallos
    ---------------------------------------------------------------------
  begin
    inicializa_test;
    DBMS_OUTPUT.PUT_LINE('Test 1: Pedido correcto');
    BEGIN
        inicializa_test;
        registrar_pedido(1, 1, 1, 2);
        DBMS_OUTPUT.PUT_LINE('Test: OK  -> Pedido realizado correctamente');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Test: FALLADO  -> Algo ha fallado, resultado no esperado' );
    END;
    
    ---------------------------------------------------------------------
    -- Test para comprobar el caso 2 de un pedido que no contenga platos
    ---------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Test 2: Pedido vacío (sin platos)');
    BEGIN
        inicializa_test;
        registrar_pedido(1, 1, NULL, NULL);
        DBMS_OUTPUT.PUT_LINE('Test: FALLADO  -> No se lanzó excepción para pedido vacío.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20002 THEN
                DBMS_OUTPUT.PUT_LINE('Test: OK  -> Excepción correcta para pedido vacío: ' || SQLERRM);
            ELSE
                DBMS_OUTPUT.PUT_LINE('Test: FALLADO  -> Excepción no controlada: ' || SQLERRM);
            END IF;
        DBMS_OUTPUT.PUT_LINE('');
    END;
  end;
  
    ---------------------------------------------------------------------------------
    -- Test para comprobar el caso 3 de un pedido que contenga un plato que no existe
    ---------------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('Test 3: Pedido con un plato que no existe');
    BEGIN
        inicializa_test;
        registrar_pedido(1, 1, 1, 5);
        DBMS_OUTPUT.PUT_LINE('Test: FALLADO  -> No se lanzó excepción para el pedido con un plato inexistente.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20004 THEN
                DBMS_OUTPUT.PUT_LINE('Test: OK  -> Excepción correcta para pedido con plato inexistente: ' || SQLERRM);
            ELSE
                DBMS_OUTPUT.PUT_LINE('Test: FALLADO  -> Excepción no controlada: ' || SQLERRM);
            END IF;
        DBMS_OUTPUT.PUT_LINE('');
    END;
    

    -----------------------------------------------------------------------------------------
    -- Test para comprobar el caso 4 de un pedido que contenga un plato que no esté disponible
    -----------------------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('Test 4: Pedido con un plato no disponible');
    BEGIN
        inicializa_test;
        registrar_pedido(1, 1, 1, 3);
        DBMS_OUTPUT.PUT_LINE('Test: FALLADO  -> No se lanzó excepción para el pedido con un plato no disponible.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20001 THEN
                DBMS_OUTPUT.PUT_LINE('Test: OK  -> Excepción correcta para pedido con plato no disponible: ' || SQLERRM);
            ELSE
                DBMS_OUTPUT.PUT_LINE('Test: FALLADO  -> Excepción no controlada: ' || SQLERRM);
            END IF;
        DBMS_OUTPUT.PUT_LINE('');
    END;
    
    --------------------------------------------------------------------------------------------------------
    -- Test para comprobar el caso 5 de un pedido a un personal de servicio con el máximo de pedidos activos
    --------------------------------------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('Test 5: Pedido a un personal de servicio con el máximo de pedidos activos');
    BEGIN
        inicializa_test;
        registrar_pedido(1, 2, 1, 2);
        DBMS_OUTPUT.PUT_LINE('Test: FALLADO  -> No se lanzó excepción para el personal de servicio con el máximo de pedidos activos.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20003 THEN
                DBMS_OUTPUT.PUT_LINE('Test: OK  -> Excepción correcta para personal de servicio con pedidos activos máximo: ' || SQLERRM);
            ELSE
                DBMS_OUTPUT.PUT_LINE('Test: FALLADO  -> Excepción no controlada: ' || SQLERRM);
            END IF;
        DBMS_OUTPUT.PUT_LINE('');
    END;

    ---------------------------------------------------------------------------------
    -- Test para comprobar el caso 6 de un pedido con un cliente que no existe
    ---------------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('Test 6: Pedido con un cliente que no existe');
    BEGIN
        inicializa_test; -- Asegura que solo existen clientes 1 y 2
        -- Llamamos con cliente 999 (inexistente), pero personal y platos válidos
        registrar_pedido(999, 1, 1, 2);
        -- Si llega aquí, es que no lanzó la excepción esperada
        DBMS_OUTPUT.PUT_LINE('Test: FALLADO  -> No se lanzó excepción para cliente inexistente.');
    EXCEPTION
        WHEN OTHERS THEN
            -- Comprobamos si el error es el esperado (-20005)
            IF SQLCODE = -20005 THEN
                DBMS_OUTPUT.PUT_LINE('Test: OK  -> Excepción correcta para cliente inexistente: ' || SQLERRM);
            ELSE
                -- Si es otro error, el test falla
                DBMS_OUTPUT.PUT_LINE('Test: FALLADO  -> Excepción no controlada: ' || SQLERRM);
            END IF;
        DBMS_OUTPUT.PUT_LINE('');
    END;

    ------------------------------------------------------------------------
    -- Test para comprobar el caso 7 de un personal de servicio inexistente
    ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('Test 7: Pedido con personal de servicio inexistente');
    BEGIN
        inicializa_test;
        registrar_pedido(1, 99, 1, 2); -- Personal 99 no existe
        DBMS_OUTPUT.PUT_LINE('Test: FALLADO  -> No se lanzó excepción para personal inexistente.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20006 THEN
                DBMS_OUTPUT.PUT_LINE('Test: OK  -> Excepción correcta para personal inexistente: ' || SQLERRM);
            ELSE
                DBMS_OUTPUT.PUT_LINE('Test: FALLADO  -> Excepción no controlada: ' || SQLERRM);
            END IF;
        DBMS_OUTPUT.PUT_LINE('');
    END;

  --end;
  -- Idem para el resto de casos

  /* - Si se realiza un pedido vac´ıo (sin platos) devuelve el error -200002.
     - Si se realiza un pedido con un plato que no existe devuelve en error -20004.
     - Si se realiza un pedido que incluye un plato que no est´a ya disponible devuelve el error -20001.
     - Personal de servicio ya tiene 5 pedidos activos y se le asigna otro pedido devuelve el error -20003
     - ... los que os puedan ocurrir que puedan ser necesarios para comprobar el correcto funcionamiento del procedimiento
*/
  
end;
/



set serveroutput on;
exec test_registrar_pedido;